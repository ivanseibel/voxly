import Foundation

enum DictationLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic = "Automático"
    case portuguese = "Português"
    case english = "Inglês"
    var id: String { rawValue }
    var whisperCode: String { self == .automatic ? "auto" : (self == .portuguese ? "pt" : "en") }
}

enum CapsuleState: Equatable {
    case ready, recording, transcribing, refining(String), inserted, copied, error(String)

    var title: String {
        switch self {
        case .ready: "Pronto"
        case .recording: "Gravando"
        case .transcribing: "Transcrevendo"
        case .refining(let name): "Ajustando: \(name)"
        case .inserted: "Inserido"
        case .copied: "Copiado — cole manualmente"
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
    var modelProfile = "Equilibrado (local)"
    var automaticInsert = true
    var usesRefinement: Bool { name != "Transcrição fiel" && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static let defaults = [
        DictationMode(name: "Transcrição fiel", shortcut: "⌘ direito", language: .automatic,
                      instructions: "Preservar fala; ajustar somente pontuação e capitalização óbvias."),
        DictationMode(name: "Limpar texto", shortcut: "⌘ direito", language: .automatic,
                      instructions: "Remover vícios de linguagem e organizar texto sem alterar significado ou fatos."),
        DictationMode(name: "E-mail profissional", shortcut: "⌘ direito", language: .automatic,
                      instructions: "Converter em e-mail claro e profissional, preservando conteúdo, nomes e solicitações."),
        DictationMode(name: "Código/notas técnicas", shortcut: "⌘ direito", language: .automatic,
                      instructions: "Organizar como nota técnica; preservar termos, identificadores, números e blocos de código ditados.")
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
