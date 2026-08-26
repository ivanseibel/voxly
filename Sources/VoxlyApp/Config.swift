import Foundation

/// User-tunable runtime settings loaded from `config.json`. Every field falls back to its
/// default when missing, so a partial or absent file never breaks startup.
struct VoxlyConfig: Codable {
    var minTapSeconds: Double = 0.3
    var whisperPort: Int = 18080
    var llamaPort: Int = 18081
    var whisperThreads: Int = 8
    var llamaThreads: Int = 8
    var engineStartRetries: Int = 7
    var retrySleepInvalidFormatSeconds: Double = 0.3
    var retrySleepStartFailureSeconds: Double = 0.4
    var tapBufferSize: Int = 2048
    var levelMeterGain: Double = 8
    var capsuleResetDelaySeconds: Double = 1.8
    var cancelKeyCode: Int = 53
    var healthCheckTimeoutSeconds: Double = 0.75
    var serverReclaimTimeoutSeconds: Double = 3.0
    var llamaContextSize: Int = 2048
    var llamaGpuLayers: String = "all"
    var refineMaxTokens: Int = 256
    var refineTemperature: Double = 0.0
    var whisperTemperature: Double = 0.0
    var whisperModelFile: String = "ggml-small.bin"
    var whisperBeamSize: Int = 5
    var whisperBestOf: Int = 5
    var whisperSuppressNonSpeech: Bool = true
    var whisperNoSpeechThreshold: Double = 0.6
    var whisperPrompt: String = ""
    var insertionDelaySeconds: Double = 0.08
    var clipboardRestoreDelaySeconds: Double = 0.65
    var a2dpRestoreTimeoutSeconds: Double = 15.0
    var a2dpRestoreGiveUpSeconds: Double = 90.0
    var a2dpRestoreNudgeEnabled: Bool = true
    var userOverrideGraceSeconds: Double = 1.5
    var volumeScriptTimeoutSeconds: Double = 6.0

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = VoxlyConfig()
        minTapSeconds = try container.decodeIfPresent(Double.self, forKey: .minTapSeconds) ?? d.minTapSeconds
        whisperPort = try container.decodeIfPresent(Int.self, forKey: .whisperPort) ?? d.whisperPort
        llamaPort = try container.decodeIfPresent(Int.self, forKey: .llamaPort) ?? d.llamaPort
        whisperThreads = try container.decodeIfPresent(Int.self, forKey: .whisperThreads) ?? d.whisperThreads
        llamaThreads = try container.decodeIfPresent(Int.self, forKey: .llamaThreads) ?? d.llamaThreads
        engineStartRetries = try container.decodeIfPresent(Int.self, forKey: .engineStartRetries) ?? d.engineStartRetries
        retrySleepInvalidFormatSeconds = try container.decodeIfPresent(Double.self, forKey: .retrySleepInvalidFormatSeconds) ?? d.retrySleepInvalidFormatSeconds
        retrySleepStartFailureSeconds = try container.decodeIfPresent(Double.self, forKey: .retrySleepStartFailureSeconds) ?? d.retrySleepStartFailureSeconds
        tapBufferSize = try container.decodeIfPresent(Int.self, forKey: .tapBufferSize) ?? d.tapBufferSize
        levelMeterGain = try container.decodeIfPresent(Double.self, forKey: .levelMeterGain) ?? d.levelMeterGain
        capsuleResetDelaySeconds = try container.decodeIfPresent(Double.self, forKey: .capsuleResetDelaySeconds) ?? d.capsuleResetDelaySeconds
        cancelKeyCode = try container.decodeIfPresent(Int.self, forKey: .cancelKeyCode) ?? d.cancelKeyCode
        healthCheckTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .healthCheckTimeoutSeconds) ?? d.healthCheckTimeoutSeconds
        serverReclaimTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .serverReclaimTimeoutSeconds) ?? d.serverReclaimTimeoutSeconds
        llamaContextSize = try container.decodeIfPresent(Int.self, forKey: .llamaContextSize) ?? d.llamaContextSize
        llamaGpuLayers = try container.decodeIfPresent(String.self, forKey: .llamaGpuLayers) ?? d.llamaGpuLayers
        refineMaxTokens = try container.decodeIfPresent(Int.self, forKey: .refineMaxTokens) ?? d.refineMaxTokens
        refineTemperature = try container.decodeIfPresent(Double.self, forKey: .refineTemperature) ?? d.refineTemperature
        whisperTemperature = try container.decodeIfPresent(Double.self, forKey: .whisperTemperature) ?? d.whisperTemperature
        whisperModelFile = try container.decodeIfPresent(String.self, forKey: .whisperModelFile) ?? d.whisperModelFile
        whisperBeamSize = try container.decodeIfPresent(Int.self, forKey: .whisperBeamSize) ?? d.whisperBeamSize
        whisperBestOf = try container.decodeIfPresent(Int.self, forKey: .whisperBestOf) ?? d.whisperBestOf
        whisperSuppressNonSpeech = try container.decodeIfPresent(Bool.self, forKey: .whisperSuppressNonSpeech) ?? d.whisperSuppressNonSpeech
        whisperNoSpeechThreshold = try container.decodeIfPresent(Double.self, forKey: .whisperNoSpeechThreshold) ?? d.whisperNoSpeechThreshold
        whisperPrompt = try container.decodeIfPresent(String.self, forKey: .whisperPrompt) ?? d.whisperPrompt
        insertionDelaySeconds = try container.decodeIfPresent(Double.self, forKey: .insertionDelaySeconds) ?? d.insertionDelaySeconds
        clipboardRestoreDelaySeconds = try container.decodeIfPresent(Double.self, forKey: .clipboardRestoreDelaySeconds) ?? d.clipboardRestoreDelaySeconds
        a2dpRestoreTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .a2dpRestoreTimeoutSeconds) ?? d.a2dpRestoreTimeoutSeconds
        a2dpRestoreGiveUpSeconds = try container.decodeIfPresent(Double.self, forKey: .a2dpRestoreGiveUpSeconds) ?? d.a2dpRestoreGiveUpSeconds
        a2dpRestoreNudgeEnabled = try container.decodeIfPresent(Bool.self, forKey: .a2dpRestoreNudgeEnabled) ?? d.a2dpRestoreNudgeEnabled
        userOverrideGraceSeconds = try container.decodeIfPresent(Double.self, forKey: .userOverrideGraceSeconds) ?? d.userOverrideGraceSeconds
        volumeScriptTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .volumeScriptTimeoutSeconds) ?? d.volumeScriptTimeoutSeconds
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.help, forKey: ._help)
        try c.encode(minTapSeconds, forKey: .minTapSeconds)
        try c.encode(whisperPort, forKey: .whisperPort)
        try c.encode(llamaPort, forKey: .llamaPort)
        try c.encode(whisperThreads, forKey: .whisperThreads)
        try c.encode(llamaThreads, forKey: .llamaThreads)
        try c.encode(engineStartRetries, forKey: .engineStartRetries)
        try c.encode(retrySleepInvalidFormatSeconds, forKey: .retrySleepInvalidFormatSeconds)
        try c.encode(retrySleepStartFailureSeconds, forKey: .retrySleepStartFailureSeconds)
        try c.encode(tapBufferSize, forKey: .tapBufferSize)
        try c.encode(levelMeterGain, forKey: .levelMeterGain)
        try c.encode(capsuleResetDelaySeconds, forKey: .capsuleResetDelaySeconds)
        try c.encode(cancelKeyCode, forKey: .cancelKeyCode)
        try c.encode(healthCheckTimeoutSeconds, forKey: .healthCheckTimeoutSeconds)
        try c.encode(serverReclaimTimeoutSeconds, forKey: .serverReclaimTimeoutSeconds)
        try c.encode(llamaContextSize, forKey: .llamaContextSize)
        try c.encode(llamaGpuLayers, forKey: .llamaGpuLayers)
        try c.encode(refineMaxTokens, forKey: .refineMaxTokens)
        try c.encode(refineTemperature, forKey: .refineTemperature)
        try c.encode(whisperTemperature, forKey: .whisperTemperature)
        try c.encode(whisperModelFile, forKey: .whisperModelFile)
        try c.encode(whisperBeamSize, forKey: .whisperBeamSize)
        try c.encode(whisperBestOf, forKey: .whisperBestOf)
        try c.encode(whisperSuppressNonSpeech, forKey: .whisperSuppressNonSpeech)
        try c.encode(whisperNoSpeechThreshold, forKey: .whisperNoSpeechThreshold)
        try c.encode(whisperPrompt, forKey: .whisperPrompt)
        try c.encode(insertionDelaySeconds, forKey: .insertionDelaySeconds)
        try c.encode(clipboardRestoreDelaySeconds, forKey: .clipboardRestoreDelaySeconds)
        try c.encode(a2dpRestoreTimeoutSeconds, forKey: .a2dpRestoreTimeoutSeconds)
        try c.encode(a2dpRestoreGiveUpSeconds, forKey: .a2dpRestoreGiveUpSeconds)
        try c.encode(a2dpRestoreNudgeEnabled, forKey: .a2dpRestoreNudgeEnabled)
        try c.encode(userOverrideGraceSeconds, forKey: .userOverrideGraceSeconds)
        try c.encode(volumeScriptTimeoutSeconds, forKey: .volumeScriptTimeoutSeconds)
    }

    private enum CodingKeys: String, CodingKey {
        case _help
        case minTapSeconds, whisperPort, llamaPort, whisperThreads, llamaThreads
        case engineStartRetries, retrySleepInvalidFormatSeconds, retrySleepStartFailureSeconds
        case tapBufferSize, levelMeterGain, capsuleResetDelaySeconds, cancelKeyCode
        case healthCheckTimeoutSeconds, serverReclaimTimeoutSeconds
        case llamaContextSize, llamaGpuLayers
        case refineMaxTokens, refineTemperature, whisperTemperature
        case whisperModelFile, whisperBeamSize, whisperBestOf
        case whisperSuppressNonSpeech, whisperNoSpeechThreshold, whisperPrompt
        case insertionDelaySeconds, clipboardRestoreDelaySeconds
        case a2dpRestoreTimeoutSeconds, a2dpRestoreGiveUpSeconds
        case a2dpRestoreNudgeEnabled, userOverrideGraceSeconds, volumeScriptTimeoutSeconds
    }

    /// Descriptions embedded in the file as a `_help` block so config.json is self-documenting.
    /// Read back is tolerant of this extra key, and it is re-emitted on every rewrite.
    private static let help: [String: String] = [
        "_note": "Edit values below and restart Voxly to apply. This _help block is informational and is ignored when loading.",
        "minTapSeconds": "Minimum hold time in seconds; shorter taps are discarded without transcribing.",
        "whisperPort": "Local TCP port for the Whisper transcription server (loopback only).",
        "llamaPort": "Local TCP port for the Llama refinement server (loopback only).",
        "whisperThreads": "CPU threads used by Whisper (server and CLI fallback).",
        "llamaThreads": "CPU threads used by the Llama refinement server.",
        "engineStartRetries": "Attempts to start audio capture before failing (helps Bluetooth negotiation).",
        "retrySleepInvalidFormatSeconds": "Wait between retries while the input device format isn't ready yet.",
        "retrySleepStartFailureSeconds": "Wait between retries after the audio engine fails to start.",
        "tapBufferSize": "Audio capture buffer size in frames.",
        "levelMeterGain": "Multiplier for the on-screen mic level meter (visual only).",
        "capsuleResetDelaySeconds": "How long the status capsule stays visible after finishing.",
        "cancelKeyCode": "macOS virtual key code that cancels an in-progress dictation (53 = Esc).",
        "healthCheckTimeoutSeconds": "Timeout in seconds for local server health checks.",
        "serverReclaimTimeoutSeconds": "Max seconds spent terminating a model server left behind by a previous run and waiting for its port to be released before launching the replacement.",
        "llamaContextSize": "Llama context window size in tokens.",
        "llamaGpuLayers": "GPU layers offloaded to Metal ('all' or a number as a string).",
        "refineMaxTokens": "Maximum tokens generated during text refinement.",
        "refineTemperature": "Sampling temperature for refinement (0 = deterministic).",
        "whisperTemperature": "Sampling temperature for transcription (0 = deterministic).",
        "whisperModelFile": "Whisper model file name inside the Models folder. Swap for a bigger model (e.g. 'ggml-large-v3-turbo-q5_0.bin') to improve accuracy at the cost of some latency.",
        "whisperBeamSize": "Beam search width for transcription. The whisper server defaults to greedy decoding; 5 matches the whisper.cpp CLI default and is noticeably more accurate.",
        "whisperBestOf": "Number of candidate transcriptions kept per decoding attempt (higher = more accurate, slower).",
        "whisperSuppressNonSpeech": "Suppress non-speech tokens so near-silent audio stops producing '[Music]'-style hallucinations.",
        "whisperNoSpeechThreshold": "Probability above which a segment is treated as silence and dropped (0.6 = whisper.cpp default; raise it if real speech is being discarded).",
        "whisperPrompt": "Vocabulary every mode inherits: proper nouns, product names and jargon, comma separated. Each mode can add its own list in the Vocabulary field of its editor; the two are combined. Empty = no bias.",
        "insertionDelaySeconds": "Delay before pasting so the target app receives the clipboard.",
        "clipboardRestoreDelaySeconds": "Delay before restoring your previous clipboard after pasting.",
        "a2dpRestoreTimeoutSeconds": "Seconds to wait for the Bluetooth A2DP profile to return before slowing the polling down to once per second (audio stays muted while waiting).",
        "a2dpRestoreGiveUpSeconds": "Hard deadline in seconds: if the A2DP baseline never returns, volume/mute are restored anyway so dictation keeps working (0 = wait forever, output may stay muted).",
        "a2dpRestoreNudgeEnabled": "Ask the Bluetooth output to return to its baseline sample rate right after capture instead of only waiting for the headset (shortens the silence after a dictation).",
        "userOverrideGraceSeconds": "How long after capture starts Voxly treats volume changes as its own fade; after that, a manual volume change hands control back to you (no re-mute, no snapshot restore).",
        "volumeScriptTimeoutSeconds": "Max seconds a volume/mute AppleScript may run before being killed, so a stuck script can never hold the audio restore back.",
    ]
}

enum AppConfig {
    /// Loaded once at launch; treated as immutable for the process lifetime.
    static let current: VoxlyConfig = load()

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voxly", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func load() -> VoxlyConfig {
        let url = fileURL
        let config: VoxlyConfig
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(VoxlyConfig.self, from: data) {
            config = decoded
            VoxlyLog.log("Loaded config from \(url.path)")
        } else {
            config = VoxlyConfig()
        }
        // Rewrite the fully resolved config so any newly added keys surface in the file
        // while preserving values the user already set.
        writeTemplate(config, to: url)
        return config
    }

    private static func writeTemplate(_ config: VoxlyConfig, to url: URL) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: url)) != nil { VoxlyLog.log("Wrote default config to \(url.path)") }
    }
}
