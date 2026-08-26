import AppKit
import Foundation

enum DictationLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic = "Automatic"
    case portuguese = "Portuguese"
    case english = "English"
    var id: String { rawValue }
    var whisperCode: String { self == .automatic ? "auto" : (self == .portuguese ? "pt" : "en") }
}

enum CapsuleState: Equatable {
    case ready, recording, transcribing, refining(String), inserted, copied, error(String)

    var title: String {
        switch self {
        case .ready: "Ready"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .refining(let name): "Refining: \(name)"
        case .inserted: "Inserted"
        case .copied: "Copied — paste manually"
        case .error(let message): message
        }
    }
}

struct DictationMode: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var shortcutKeyCode = 54  // Right Command
    var language: DictationLanguage
    var instructions: String
    /// Proper nouns, product names and jargon biasing transcription for this mode
    /// (Whisper initial prompt). Kept per mode because a technical-notes dictation
    /// and an email dictation rarely need the same words. Combined with the global
    /// `whisperPrompt` config key at transcription time.
    var vocabulary = ""
    var modelProfile = "Balanced (local)"
    var automaticInsert = true
    var usesRefinement: Bool { name != "Faithful transcription" && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Human-readable name (e.g. "⌘ Right"), computed from shortcutKeyCode.
    var shortcut: String { Self.name(for: shortcutKeyCode) }
    /// ModifierFlags rawValue derived from shortcutKeyCode — used by DictationCoordinator.
    var shortcutModifiers: UInt { Self.modifierFlag(for: shortcutKeyCode).rawValue }

    static let defaults = [
        DictationMode(name: "Faithful transcription", language: .automatic,
                      instructions: "Preserve speech; adjust only obvious punctuation and capitalization."),
        DictationMode(name: "Clean text", language: .automatic,
                      instructions: "Remove filler words and organize text without changing meaning or facts."),
        DictationMode(name: "Professional email", language: .automatic,
                      instructions: "Convert into a clear, professional email, preserving content, names, and requests."),
        DictationMode(name: "Code/technical notes", language: .automatic,
                      instructions: "Organize as a technical note; preserve terms, identifiers, names, and dictated code blocks.")
    ]

    // MARK: - Shortcut key mapping
    private static let keyNames: [Int: String] = [
        54: "⌘ Right", 55: "⌘ Left", 56: "⇧ Left", 58: "⌥ Left",
        59: "⌃ Left", 60: "⇧ Right", 61: "⌥ Right", 62: "⌃ Right", 63: "Fn",
    ]
    static let modifierKeyCodes: Set<Int> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    static func name(for keyCode: Int) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    static func modifierFlag(for keyCode: Int) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 54, 55: .command
        case 56, 60: .shift
        case 58, 61: .option
        case 59, 62: .control
        case 63:     .function
        default:     .command
        }
    }

    // MARK: - Codable (backward compat with old shortcut-only data)
    enum CodingKeys: String, CodingKey {
        case id, name, shortcutKeyCode, language, instructions, vocabulary, modelProfile, automaticInsert
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        shortcutKeyCode = try c.decodeIfPresent(Int.self, forKey: .shortcutKeyCode) ?? 54
        language = try c.decodeIfPresent(DictationLanguage.self, forKey: .language) ?? .automatic
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        vocabulary = try c.decodeIfPresent(String.self, forKey: .vocabulary) ?? ""
        modelProfile = try c.decodeIfPresent(String.self, forKey: .modelProfile) ?? "Balanced (local)"
        automaticInsert = try c.decodeIfPresent(Bool.self, forKey: .automaticInsert) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(shortcutKeyCode, forKey: .shortcutKeyCode)
        try c.encode(language, forKey: .language)
        try c.encode(instructions, forKey: .instructions)
        try c.encode(vocabulary, forKey: .vocabulary)
        try c.encode(modelProfile, forKey: .modelProfile)
        try c.encode(automaticInsert, forKey: .automaticInsert)
    }

    init(id: UUID = UUID(), name: String, shortcutKeyCode: Int = 54, language: DictationLanguage,
         instructions: String, vocabulary: String = "", modelProfile: String = "Balanced (local)",
         automaticInsert: Bool = true) {
        self.id = id
        self.name = name
        self.shortcutKeyCode = shortcutKeyCode
        self.language = language
        self.instructions = instructions
        self.vocabulary = vocabulary
        self.modelProfile = modelProfile
        self.automaticInsert = automaticInsert
    }
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var rawText: String
    var finalText: String
    var mode: String
    var language: DictationLanguage
    var createdAt = Date()
    var insertion: InsertionResult
}

enum InsertionResult: String, Codable { case inserted, copied, failed }

struct PermissionStatus: Equatable {
    var microphone = false
    var accessibility = false
    var models = false
    var allReady: Bool { microphone && accessibility && models }
}
