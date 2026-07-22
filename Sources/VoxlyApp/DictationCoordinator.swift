import AppKit
import Foundation

@MainActor
final class DictationCoordinator: NSObject {
    private let store: VoxlyStore
    private let recorder = AudioRecorder()
    private let permissions = PermissionManager()
    private let transcriber = LocalTranscriber()
    private let refiner = LocalRefiner()
    private let inserter = TextInserter()
    private var target: TextInserter.Target?
    private var monitor: Any?
    private var isRecording = false
    var onCapsule: ((Bool) -> Void)?

    init(store: VoxlyStore) { self.store = store; super.init(); recorder.onLevel = { [weak store] in store?.audioLevel = $0 } }
    func start() {
        refreshStatus()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let type = event.type; let keyCode = event.keyCode; let flags = event.modifierFlags
            DispatchQueue.main.async { self?.receive(type: type, keyCode: keyCode, modifierFlags: flags) }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let type = event.type; let keyCode = event.keyCode; let flags = event.modifierFlags
            DispatchQueue.main.async { self?.receive(type: type, keyCode: keyCode, modifierFlags: flags) }
            return event
        }
    }
    func refreshStatus() { store.status = permissions.refresh() }
    func requestMicrophone() async { _ = await permissions.requestMicrophone(); refreshStatus() }
    func requestAccessibility() { permissions.requestAccessibility(); refreshStatus() }
    func receive(type: NSEvent.EventType, keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        if type == .keyDown, keyCode == 53 { cancel(); return }
        guard store.activeMode.shortcut == "⌘ Right" else { return }
        guard keyCode == 54 else { return } // right Command hardware key
        let pressed = modifierFlags.contains(.command)
        if pressed && !isRecording { begin() }
        if !pressed && isRecording { finish() }
    }
    func begin() {
        guard store.status.microphone else { fail("Allow Microphone to record"); return }
        guard store.status.accessibility else { fail("Allow Accessibility to insert text"); return }
        guard store.status.models else { fail("Install local models before dictating"); return }
        target = inserter.captureTarget()
        do { try recorder.start(); recordingStartedAt = Date(); isRecording = true; store.capsule = .recording; store.lastMessage = "Recording — release ⌘ Right"; onCapsule?(true) }
        catch { fail(error.localizedDescription) }
    }
    private var recordingStartedAt: Date?
    func finish() {
        guard isRecording else { return }
        isRecording = false
        let audio = recorder.stopAndRemove(); store.audioLevel = 0
        let heldSeconds = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil
        guard heldSeconds >= 0.3 else {
            VoxlyLog.log("Tap too short (\(String(format: "%.2f", heldSeconds))s) — discarding without transcribing")
            if let audio { try? FileManager.default.removeItem(at: audio) }
            store.capsule = .ready; store.lastMessage = "Tap too short — hold ⌘ Right while speaking"; onCapsule?(false)
            return
        }
        store.capsule = .transcribing
        store.lastMessage = "Processing audio locally"
        onCapsule?(true)
        Task { await process(audio) }
    }
    func cancel() {
        guard isRecording || store.capsule != .ready else { return }
        isRecording = false; _ = recorder.stopAndRemove(); recorder.discard(); store.audioLevel = 0; store.capsule = .ready; store.lastMessage = "Dictation canceled"; onCapsule?(false)
    }
    private func process(_ audio: URL?) async {
        guard let audio else { fail("No usable audio captured"); return }
        let startedAt = Date()
        var shouldRemoveAudio = true
        defer { if shouldRemoveAudio { try? FileManager.default.removeItem(at: audio) } }
        do {
            let raw = try await Task.detached { [transcriber, mode = store.activeMode] in try await transcriber.transcribe(audio: audio, language: mode.language) }.value
            let transcriptionSeconds = Date().timeIntervalSince(startedAt)
            let mode = store.activeMode
            let final: String
            if !mode.usesRefinement {
                VoxlyLog.log("Mode '\(mode.name)' has no refinement (usesRefinement=false)")
                final = raw
            }
            else {
                VoxlyLog.log("Starting refinement — mode: '\(mode.name)', instructions: \(mode.instructions.prefix(60))...")
                store.capsule = .refining(mode.name)
                store.lastMessage = "Refining text locally"
                onCapsule?(true)
                do { final = try await Task.detached { [refiner] in try await refiner.refine(raw, mode: mode) }.value }
                catch {
                    VoxlyLog.log("Refinement failed completely: \(error) — using raw text")
                    final = raw; store.lastMessage = "Refinement failed; raw text kept"
                }
            }
            let result = target.map { inserter.insert(final + " ", into: $0) } ?? .failed
            store.addHistory(raw: raw, final: final, result: result)
            store.capsule = result == .inserted ? .inserted : .copied
            let elapsed = String(format: "%.1f", Date().timeIntervalSince(startedAt))
            let transcribed = String(format: "%.1f", transcriptionSeconds)
            store.lastMessage = result == .inserted ? "Text inserted · processed \(elapsed)s (Whisper \(transcribed)s)" : "Text in clipboard · processed \(elapsed)s"
            onCapsule?(true); DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.store.capsule = .ready; self?.onCapsule?(false) }
        } catch {
            shouldRemoveAudio = false
            if let saved = Self.preserveAudioForDebug(audio) { VoxlyLog.log("Audio from failure preserved at: \(saved.path)") }
            fail(error.localizedDescription)
        }
    }
    private static func preserveAudioForDebug(_ audio: URL) -> URL? {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voxly/FailedAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(audio.lastPathComponent)
        do { try FileManager.default.moveItem(at: audio, to: dest); return dest }
        catch { return nil }
    }
    private func fail(_ message: String) {
        VoxlyLog.log("Failure: \(message)")
        store.capsule = .error(message); store.lastMessage = message; onCapsule?(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, case .error = self.store.capsule else { return }
            self.store.capsule = .ready; self.onCapsule?(false)
        }
    }
}
