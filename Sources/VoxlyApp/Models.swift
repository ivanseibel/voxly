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
    var shortcut: String
    var language: DictationLanguage
    var instructions: String
    var modelProfile = "Balanced (local)"
    var automaticInsert = true
    var usesRefinement: Bool { name != "Faithful transcription" && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static let defaults = [
        DictationMode(name: "Faithful transcription", shortcut: "⌘ Right", language: .automatic,
                      instructions: "Preserve speech; adjust only obvious punctuation and capitalization."),
        DictationMode(name: "Clean text", shortcut: "⌘ Right", language: .automatic,
                      instructions: "Remove filler words and organize text without changing meaning or facts."),
        DictationMode(name: "Professional email", shortcut: "⌘ Right", language: .automatic,
                      instructions: "Convert into a clear, professional email, preserving content, names, and requests."),
        DictationMode(name: "Code/technical notes", shortcut: "⌘ Right", language: .automatic,
                      instructions: "Organize as a technical note; preserve terms, identifiers, numbers, and dictated code blocks.")
    ]
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
