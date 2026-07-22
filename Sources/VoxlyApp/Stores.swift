import Foundation
import SwiftUI

@MainActor
final class VoxlyStore: ObservableObject {
    @Published var modes: [DictationMode] { didSet { saveModes() } }
    @Published var activeModeID: UUID { didSet { defaults.set(activeModeID.uuidString, forKey: "activeModeID") } }
    @Published var history: [HistoryEntry] { didSet { saveHistory() } }
    @Published var status = PermissionStatus()
    @Published var capsule: CapsuleState = .ready
    @Published var audioLevel: Float = 0
    @Published var lastMessage = "Ready to dictate"

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default

    init() {
        let initialModes = Self.decode([DictationMode].self, key: "modes") ?? DictationMode.defaults
        let savedActiveID = UUID(uuidString: defaults.string(forKey: "activeModeID") ?? "")
        modes = initialModes
        activeModeID = savedActiveID.flatMap { id in initialModes.contains(where: { $0.id == id }) ? id : nil } ?? initialModes[0].id
        history = Self.decode([HistoryEntry].self, key: "history") ?? []
    }

    var activeMode: DictationMode { modes.first(where: { $0.id == activeModeID }) ?? modes[0] }

    func addHistory(raw: String, final: String, result: InsertionResult) {
        history.insert(HistoryEntry(rawText: raw, finalText: final, mode: activeMode.name, language: activeMode.language, insertion: result), at: 0)
    }
    func deleteHistory(_ entry: HistoryEntry) { history.removeAll { $0.id == entry.id } }
    func clearHistory() { history = [] }
    func shortcutTaken(_ shortcut: String, excluding id: UUID? = nil) -> Bool {
        modes.contains { $0.shortcut == shortcut && $0.id != id }
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
