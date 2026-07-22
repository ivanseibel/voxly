import SwiftUI

struct ContentView: View {
    @ObservedObject var store: VoxlyStore
    let coordinator: DictationCoordinator
    @State private var section: Section = .modes
    enum Section: String, CaseIterable, Identifiable { case modes = "Modes", history = "History", diagnosis = "Diagnostics"; var id: String { rawValue } }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                BrandMark()
                Spacer().frame(height: 28)
                ForEach(Section.allCases) { item in
                    Button { section = item } label: { Label(item.rawValue, systemImage: icon(item)).frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(NavButton(selected: section == item))
                }
                Spacer()
                StatusStrip(status: store.status)
            }
            .padding(18).frame(width: 190).background(VoxlyColor.canvas)
            Divider().overlay(VoxlyColor.line)
            VStack(spacing: 0) { Header(store: store); Divider().overlay(VoxlyColor.line); Group { switch section { case .modes: ModesView(store: store); case .history: HistoryView(store: store); case .diagnosis: DiagnosisView(store: store, coordinator: coordinator) } }.frame(maxWidth: .infinity, maxHeight: .infinity) }
                .background(VoxlyColor.base)
        }
        .frame(minWidth: 820, minHeight: 560).preferredColorScheme(.dark)
    }
    func icon(_ item: Section) -> String { switch item { case .modes: "slider.horizontal.3"; case .history: "clock.arrow.circlepath"; case .diagnosis: "stethoscope" } }
}

enum VoxlyColor { static let base = Color(red: 0.055, green: 0.06, blue: 0.065); static let canvas = Color(red: 0.075, green: 0.08, blue: 0.085); static let raised = Color(red: 0.10, green: 0.105, blue: 0.11); static let inset = Color.black.opacity(0.24); static let line = Color.white.opacity(0.10); static let softLine = Color.white.opacity(0.06); static let ink = Color.white.opacity(0.92); static let muted = Color.white.opacity(0.48) }

struct BrandMark: View { var body: some View { HStack(spacing: 9) { Image(systemName: "waveform").foregroundStyle(.green).font(.system(size: 18, weight: .medium)); Text("Voxly").font(.system(size: 19, weight: .semibold, design: .rounded)) }.foregroundStyle(VoxlyColor.ink) } }
struct NavButton: ButtonStyle { let selected: Bool; func makeBody(configuration: Configuration) -> some View { configuration.label.padding(.horizontal, 10).padding(.vertical, 8).foregroundStyle(selected ? Color.white : VoxlyColor.muted).background(selected ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7)).opacity(configuration.isPressed ? 0.7 : 1) } }
struct StatusStrip: View { let status: PermissionStatus; var body: some View { VStack(alignment: .leading, spacing: 5) { HStack(spacing: 6) { Circle().fill(status.allReady ? .green : .orange).frame(width: 7, height: 7); Text(status.allReady ? "Ready" : "Attention needed").font(.caption.weight(.medium)) }; Text(status.allReady ? "All local on this Mac" : "Open Diagnostics").font(.caption2).foregroundStyle(VoxlyColor.muted) }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(VoxlyColor.raised, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(VoxlyColor.line)) } }
struct Header: View { @ObservedObject var store: VoxlyStore; var body: some View { HStack { VStack(alignment: .leading, spacing: 3) { Text(store.activeMode.name).font(.headline); Text(store.lastMessage).font(.caption).foregroundStyle(VoxlyColor.muted) }; Spacer(); Text(store.activeMode.shortcut).font(.system(.caption, design: .monospaced).weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6).background(VoxlyColor.inset, in: RoundedRectangle(cornerRadius: 6)) }.padding(.horizontal, 28).padding(.vertical, 18) } }

struct ModesView: View {
    @ObservedObject var store: VoxlyStore
    @State private var selectedID: UUID?
    @State private var draft: DictationMode?
    @State private var error = ""
    var selected: DictationMode? { store.modes.first { $0.id == (selectedID ?? store.activeModeID) } }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Speech modes").font(.title2.weight(.semibold)).padding(.bottom, 10)
                ForEach(store.modes) { mode in
                    Button { selectedID = mode.id; draft = mode; error = "" } label: {
                        HStack(spacing: 10) { Circle().fill(mode.id == store.activeModeID ? .green : .clear).frame(width: 7, height: 7); VStack(alignment: .leading, spacing: 2) { Text(mode.name); Text(mode.language.rawValue).font(.caption).foregroundStyle(VoxlyColor.muted) }; Spacer(); Text(mode.shortcut).font(.system(.caption, design: .monospaced)).foregroundStyle(VoxlyColor.muted) }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(NavButton(selected: mode.id == (selectedID ?? store.activeModeID)))
                }
                Button { let new = DictationMode(name: "New mode", shortcut: "⌘ Right", language: .automatic, instructions: ""); store.modes.append(new); selectedID = new.id; draft = new } label: { Label("New mode", systemImage: "plus") }.padding(.top, 8)
                Spacer()
            }.padding(28).frame(width: 300).background(VoxlyColor.canvas)
            Divider().overlay(VoxlyColor.line)
            if let binding = Binding($draft) {
                ModeEditor(mode: binding, error: $error, save: save)
            } else { ContentUnavailableView("Select a mode", systemImage: "waveform", description: Text("Configure language, shortcut, and local instructions.")) }
        }.onAppear { selectedID = store.activeModeID; draft = selected }
    }
    func save() {
        guard let draft else { return }
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Name required"; return }
        guard let index = store.modes.firstIndex(where: { $0.id == draft.id }) else { return }
        store.modes[index] = draft; store.activeModeID = draft.id; error = "Saved"
    }
}

struct ModeEditor: View {
    @Binding var mode: DictationMode
    @Binding var error: String
    let save: () -> Void
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 22) {
            Text("Edit mode").font(.title2.weight(.semibold))
            Field(label: "Name") { TextField("Name", text: $mode.name) }
            HStack(spacing: 14) { Field(label: "Global shortcut") { Text("Right ⌘ — press and hold").foregroundStyle(VoxlyColor.muted) }; Field(label: "Language") { Picker("Language", selection: $mode.language) { ForEach(DictationLanguage.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading) } }
            Field(label: "Local instructions") { TextEditor(text: $mode.instructions).font(.body).scrollContentBackground(.hidden).frame(minHeight: 145).padding(8).background(VoxlyColor.inset, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(VoxlyColor.line)) }
            HStack { VStack(alignment: .leading, spacing: 2) { Text("Output").font(.caption.weight(.medium)).foregroundStyle(VoxlyColor.muted); Text("Insert automatically; clipboard as fallback").font(.subheadline) }; Spacer(); Toggle("", isOn: $mode.automaticInsert).labelsHidden().toggleStyle(.switch) }
                .padding(12).background(VoxlyColor.raised, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(VoxlyColor.line))
            HStack { if !error.isEmpty { Text(error).font(.caption).foregroundStyle(error == "Saved" ? .green : .orange) }; Spacer(); Button("Save mode", action: save).buttonStyle(.borderedProminent).tint(.green) }
        }.padding(30) }
    }
}

struct Field<Content: View>: View { let label: String; @ViewBuilder let content: Content; var body: some View { VStack(alignment: .leading, spacing: 7) { Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(VoxlyColor.muted); content.textFieldStyle(.plain).padding(10).background(VoxlyColor.inset, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(VoxlyColor.line)) } } }

struct HistoryView: View {
    @ObservedObject var store: VoxlyStore
    @State private var query = ""
    var entries: [HistoryEntry] { query.isEmpty ? store.history : store.history.filter { $0.finalText.localizedCaseInsensitiveContains(query) || $0.rawText.localizedCaseInsensitiveContains(query) } }
    var body: some View { VStack(alignment: .leading, spacing: 20) { HStack { VStack(alignment: .leading, spacing: 3) { Text("Local history").font(.title2.weight(.semibold)); Text("Text only. Audio is never preserved.").font(.caption).foregroundStyle(VoxlyColor.muted) }; Spacer(); if !store.history.isEmpty { Button("Delete all", role: .destructive) { store.clearHistory() } } }.padding(.horizontal, 28).padding(.top, 25)
        TextField("Search text", text: $query).textFieldStyle(.plain).padding(10).background(VoxlyColor.inset, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(VoxlyColor.line)).padding(.horizontal, 28)
        if entries.isEmpty { Spacer(); ContentUnavailableView("No transcriptions", systemImage: "text.quote", description: Text("Local results appear here.")); Spacer() } else { List { ForEach(entries) { entry in HistoryRow(entry: entry, delete: { store.deleteHistory(entry) }) }.listRowBackground(VoxlyColor.base) }.scrollContentBackground(.hidden) }
    } }
}
struct HistoryRow: View { let entry: HistoryEntry; let delete: () -> Void; var body: some View { HStack(alignment: .top, spacing: 12) { Image(systemName: entry.insertion == .inserted ? "checkmark.circle.fill" : "doc.on.clipboard").foregroundStyle(entry.insertion == .inserted ? .green : .blue); VStack(alignment: .leading, spacing: 5) { Text(entry.finalText).lineLimit(2); HStack(spacing: 7) { Text(entry.mode); Text("·"); Text(entry.createdAt, format: .dateTime.day().month().hour().minute()); Text("·"); Text(entry.language.rawValue) }.font(.caption).foregroundStyle(VoxlyColor.muted) }; Spacer(); Button(action: delete) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(VoxlyColor.muted) }.padding(.vertical, 7) } }

struct DiagnosisView: View {
    @ObservedObject var store: VoxlyStore
    let coordinator: DictationCoordinator
    var body: some View { VStack(alignment: .leading, spacing: 24) { Text("Diagnostics").font(.title2.weight(.semibold)); Text("Voxly only enables dictation once permissions and local models are available.").foregroundStyle(VoxlyColor.muted)
        CheckRow(title: "Microphone", detail: "Captures voice while shortcut is held", ok: store.status.microphone, action: { Task { await coordinator.requestMicrophone() } })
        CheckRow(title: "Accessibility", detail: "Inserts result into the originally focused field", ok: store.status.accessibility, action: coordinator.requestAccessibility)
        CheckRow(title: "Local models", detail: "Whisper + refinement model in private storage", ok: store.status.models, actionLabel: "Open folder", action: { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ModelLocator.shared.installFolder) })
        VStack(alignment: .leading, spacing: 5) { Text("Models folder").font(.caption.weight(.medium)).foregroundStyle(VoxlyColor.muted); Text(ModelLocator.shared.installFolder).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }.padding(12).background(VoxlyColor.inset, in: RoundedRectangle(cornerRadius: 8))
        Spacer()
    }.padding(30) }
}
struct CheckRow: View { let title: String; let detail: String; let ok: Bool; var actionLabel = "Allow"; let action: () -> Void; var body: some View { HStack(spacing: 14) { Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? .green : .orange).font(.title3); VStack(alignment: .leading, spacing: 3) { Text(title).fontWeight(.medium); Text(detail).font(.caption).foregroundStyle(VoxlyColor.muted) }; Spacer(); if !ok { Button(actionLabel, action: action).buttonStyle(.bordered) } }.padding(13).background(VoxlyColor.raised, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(VoxlyColor.line)) } }
