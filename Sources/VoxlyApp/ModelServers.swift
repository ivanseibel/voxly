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
            if !(await responds(to: LocalModelHTTP.whisperHealthURL)) {
                whisper = launch(ModelLocator.shared.whisperServer, arguments: ["--host", "127.0.0.1", "--port", "18080", "-m", ModelLocator.shared.whisperModel.path, "-t", "8"])
            }
            if !(await responds(to: LocalModelHTTP.llamaHealthURL)) {
                llama = launch(ModelLocator.shared.llamaServer, arguments: ["--host", "127.0.0.1", "--port", "18081", "-m", ModelLocator.shared.instructModel.path, "-ngl", "all", "-t", "8", "-c", "2048", "--reasoning", "off", "--no-webui"])
            }
        }
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
        request.timeoutInterval = 0.75
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
    static let whisperURL = URL(string: "http://127.0.0.1:18080/inference")!
    static let llamaURL = URL(string: "http://127.0.0.1:18081/v1/chat/completions")!
    static let whisperHealthURL = URL(string: "http://127.0.0.1:18080/health")!
    static let llamaHealthURL = URL(string: "http://127.0.0.1:18081/health")!

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
        ], max_tokens: 256, temperature: 0.0, stream: false)
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
