import Foundation
import SwiftUI

@MainActor
final class VoxlyStore: ObservableObject {
    @Published var modes: [DictationMode] { didSet { saveModes() } }
    @Published var history: [HistoryEntry] { didSet { saveHistory() } }
    @Published var status = PermissionStatus()
    @Published var capsule: CapsuleState = .ready
    @Published var audioLevel: Float = 0
    @Published var lastMessage = "Ready to dictate"

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default

    init() {
        modes = Self.decode([DictationMode].self, key: "modes") ?? DictationMode.defaults
        history = Self.decode([HistoryEntry].self, key: "history") ?? []
    }

    func addHistory(raw: String, final: String, result: InsertionResult, mode: DictationMode) {
        history.insert(HistoryEntry(rawText: raw, finalText: final, mode: mode.name, language: mode.language, insertion: result), at: 0)
    }
    func deleteHistory(_ entry: HistoryEntry) { history.removeAll { $0.id == entry.id } }
    func clearHistory() { history = [] }
    func shortcutKeyTaken(_ keyCode: Int, excluding id: UUID? = nil) -> Bool {
        modes.contains { $0.shortcutKeyCode == keyCode && $0.id != id }
    }

    private func saveModes() { Self.encode(modes, key: "modes") }
    private func saveHistory() { Self.encode(history, key: "history") }
    private static func encode<T: Encodable>(_ value: T, key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
