import Foundation

@MainActor
final class ModelServerManager {
    static let shared = ModelServerManager()
    private var whisper: Process?
    private var llama: Process?
    private(set) var started = false

    func start() {
        guard !started else { return }
        started = true
        Task { @MainActor in
            whisper = await launchOwned(
                executable: ModelLocator.shared.whisperServer,
                port: AppConfig.current.whisperPort,
                health: LocalModelHTTP.whisperHealthURL,
                arguments: ["--host", "127.0.0.1", "--port", "\(AppConfig.current.whisperPort)", "-m", ModelLocator.shared.whisperModel.path, "-t", "\(AppConfig.current.whisperThreads)"])
            llama = await launchOwned(
                executable: ModelLocator.shared.llamaServer,
                port: AppConfig.current.llamaPort,
                health: LocalModelHTTP.llamaHealthURL,
                arguments: ["--host", "127.0.0.1", "--port", "\(AppConfig.current.llamaPort)", "-m", ModelLocator.shared.instructModel.path, "-ngl", AppConfig.current.llamaGpuLayers, "-t", "\(AppConfig.current.llamaThreads)", "-c", "\(AppConfig.current.llamaContextSize)", "--reasoning", "off", "--no-webui"])
        }
    }

    /// Ends up owning the server process instead of adopting one that is already answering.
    /// An adopted server can't be terminated on quit — `stop()` only owns what it launched —
    /// so it survives every restart as an orphan, still holding the model and settings of the
    /// run that spawned it. That is why changing `whisperModelFile` had no effect until the
    /// leftover process was killed by hand.
    private func launchOwned(executable: URL, port: Int, health: URL, arguments: [String]) async -> Process? {
        if await responds(to: health) {
            guard reclaim(port: port, executable: executable) else { return nil }
            await waitForPortRelease(health: health)
        }
        return launch(executable, arguments: arguments)
    }

    /// Terminates leftover servers holding `port`. Returns false when the port belongs to a
    /// process Voxly didn't spawn, in which case the existing server is left running and
    /// reused rather than killed.
    private func reclaim(port: Int, executable: URL) -> Bool {
        let listening = (try? LocalProcess.run(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-ti", "tcp:\(port)", "-sTCP:LISTEN"],
            timeout: AppConfig.current.serverReclaimTimeoutSeconds)) ?? ""
        let pids = listening.split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
        guard !pids.isEmpty else { return true }
        var reclaimedEveryPID = true
        for pid in pids {
            let command = (try? LocalProcess.run(
                executable: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-p", "\(pid)", "-o", "command="],
                timeout: AppConfig.current.serverReclaimTimeoutSeconds)) ?? ""
            guard command.contains(executable.path) else {
                VoxlyLog.log("Port \(port) is held by a process Voxly didn't launch (pid \(pid)) — reusing it instead of killing it")
                reclaimedEveryPID = false
                continue
            }
            kill(pid, SIGTERM)
            VoxlyLog.log("Terminated orphaned \(executable.lastPathComponent) (pid \(pid)) so the new one loads the current config")
        }
        return reclaimedEveryPID
    }

    /// SIGTERM is asynchronous and the port stays bound for a moment. A replacement that
    /// loses the bind race dies silently, because server output goes to `/dev/null`.
    private func waitForPortRelease(health: URL) async {
        let deadline = Date().addingTimeInterval(AppConfig.current.serverReclaimTimeoutSeconds)
        while Date() < deadline {
            if !(await responds(to: health)) { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        VoxlyLog.log("Orphaned server still answering \(health.absoluteString) — launching the replacement anyway")
    }

    func stop() {
        if whisper?.isRunning == true { whisper?.terminate() }
        if llama?.isRunning == true { llama?.terminate() }
        whisper = nil
        llama = nil
        started = false
    }

    private func responds(to url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = AppConfig.current.healthCheckTimeoutSeconds
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    private func launch(_ executable: URL, arguments: [String]) -> Process? {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); return process } catch { return nil }
    }
}

enum LocalModelHTTP {
    static var whisperURL: URL { URL(string: "http://127.0.0.1:\(AppConfig.current.whisperPort)/inference")! }
    static var llamaURL: URL { URL(string: "http://127.0.0.1:\(AppConfig.current.llamaPort)/v1/chat/completions")! }
    static var whisperHealthURL: URL { URL(string: "http://127.0.0.1:\(AppConfig.current.whisperPort)/health")! }
    static var llamaHealthURL: URL { URL(string: "http://127.0.0.1:\(AppConfig.current.llamaPort)/health")! }

    static func multipart(url: URL, file: URL, fields: [String: String]) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let filename = file.lastPathComponent
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: file)); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw VoxlyError.processFailed("Whisper server unavailable") }
        return data
    }

    static func chat(system: String, prompt: String) async throws -> String {
        let payload = ChatRequest(messages: [
            Message(role: "system", content: system),
            Message(role: "user", content: prompt)
        ], max_tokens: AppConfig.current.refineMaxTokens, temperature: AppConfig.current.refineTemperature, stream: false)
        var request = URLRequest(url: llamaURL); request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(payload); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw VoxlyError.processFailed("Llama server unavailable") }
        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }

    struct WhisperResponse: Decodable { let text: String }
    struct Message: Codable { let role: String; let content: String }
    struct ChatRequest: Encodable { let messages: [Message]; let max_tokens: Int; let temperature: Double; let stream: Bool }
    struct ChatChoice: Decodable { let message: Message }
    struct ChatResponse: Decodable { let choices: [ChatChoice] }
}
