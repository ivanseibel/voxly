import AppKit
import SwiftUI

@main
struct VoxlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Voxly", id: "main") { ContentView(store: delegate.store, coordinator: delegate.coordinator) }
            .defaultSize(width: 860, height: 620)
            .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = VoxlyStore()
    lazy var coordinator = DictationCoordinator(store: store)
    private let capsule = CapsulePanelController()
    private var statusItemController: StatusItemController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        ModelServerManager.shared.start()
        statusItemController = StatusItemController(store: store, coordinator: coordinator)
        coordinator.onCapsule = { [weak self] visible in self?.capsule.set(visible: visible, state: self?.store.capsule ?? .ready, level: self?.store.audioLevel ?? 0) }
        coordinator.start()
    }
    func applicationWillTerminate(_ notification: Notification) {
        coordinator.cancel()
        ModelServerManager.shared.stop()
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init(store: VoxlyStore, coordinator: DictationCoordinator) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.icon()
            button.imagePosition = .imageOnly
            button.toolTip = "Voxly"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 260, height: 300)
        popover.contentViewController = NSHostingController(rootView: MenuBarView(store: store, coordinator: coordinator))
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private static func icon() -> NSImage {
        if let url = Bundle.main.url(forResource: "VoxlyMenuBar", withExtension: "png"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Voxly") ?? NSImage()
    }
}

struct MenuBarView: View {
    @ObservedObject var store: VoxlyStore
    let coordinator: DictationCoordinator
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Circle().fill(store.status.allReady ? .green : .orange).frame(width: 8, height: 8); Text(store.capsule.title).fontWeight(.semibold); Spacer(); Text("local").foregroundStyle(.secondary) }
            Divider()
            Text("Active mode").font(.caption).foregroundStyle(.secondary)
            Picker("Mode", selection: $store.activeModeID) { ForEach(store.modes) { Text($0.name).tag($0.id) } }.labelsHidden()
            Text("Hold \(store.activeMode.shortcut) to dictate").font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Open Voxly") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Check permissions") { coordinator.refreshStatus() }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(14).frame(width: 260)
    }
}

@MainActor
final class CapsulePanelController {
    private var panel: NSPanel?
    func set(visible: Bool, state: CapsuleState, level: Float) {
        guard visible else { panel?.orderOut(nil); return }
        let view = NSHostingView(rootView: CapsuleView(state: state, level: level))
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 286, height: 64), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .floating; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.ignoresMouseEvents = true; panel = p
        }
        panel?.contentView = view
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let screen {
            let frame = screen.visibleFrame
            let panelSize = panel?.frame.size ?? NSSize(width: 286, height: 64)
            let margin: CGFloat = 24
            panel?.setFrameOrigin(NSPoint(
                x: frame.midX - panelSize.width / 2,
                y: frame.minY + margin
            ))
        }
        panel?.orderFrontRegardless()
    }
}

struct CapsuleView: View {
    let state: CapsuleState
    let level: Float
    var tint: Color { switch state { case .recording: .green; case .transcribing, .refining: .orange; case .inserted: .green; case .copied: .blue; case .error: .red; case .ready: .secondary } }
    var isProcessing: Bool { if case .transcribing = state { return true }; if case .refining = state { return true }; return false }
    var detail: String {
        switch state {
        case .recording: ""
        case .transcribing: "Processing audio on this Mac"
        case .refining: "Applying mode locally"
        case .inserted: "Text inserted into field"
        case .copied: "Result in clipboard"
        case .error: "Check Diagnostics"
        case .ready: "Ready to dictate"
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            ZStack { Circle().fill(tint.opacity(0.18)).frame(width: 34, height: 34); if isProcessing { ProgressView().controlSize(.small).tint(tint) } else { Image(systemName: state == .recording ? "waveform" : "ellipsis").foregroundStyle(tint) } }
            VStack(alignment: .leading, spacing: 5) {
                Text(state.title).font(.system(size: 13, weight: .semibold))
                if state == .recording { CapsuleMeter(level: level).frame(height: 5) } else { Text(detail).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(.horizontal, 14).frame(width: 286, height: 64)
        .background(.black.opacity(0.90), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
        .foregroundStyle(.white)
    }
}

struct CapsuleMeter: View {
    let level: Float
    var body: some View { GeometryReader { proxy in Capsule().fill(.white.opacity(0.15)).overlay(alignment: .leading) { Capsule().fill(.green).frame(width: max(6, proxy.size.width * CGFloat(level))) } } }
}
