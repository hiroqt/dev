import AppKit
import SwiftUI

@MainActor
final class DevAppDelegate: NSObject, NSApplicationDelegate {
    let store = WorkspaceStore()
    private var notchPanel: NotchSummaryPanelController?
    private var settingsObserver: NSObjectProtocol?
    private var miniaturizeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["quickSummaryEnabled": true])
        notchPanel = NotchSummaryPanelController(store: store)
        notchPanel?.setEnabled(UserDefaults.standard.bool(forKey: "quickSummaryEnabled"))
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.notchPanel?.setEnabled(UserDefaults.standard.bool(forKey: "quickSummaryEnabled")) }
        }
        miniaturizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMiniaturizeNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow, !(window is NSPanel) else { return }
            Task { @MainActor in self?.notchPanel?.showExpanded() }
        }
        Task {
            await store.restoreSession()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchPanel?.stop()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let miniaturizeObserver { NotificationCenter.default.removeObserver(miniaturizeObserver) }
    }
}

@main
struct DevApp: App {
    @NSApplicationDelegateAdaptor(DevAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "workspace") {
            WorkspaceView(store: appDelegate.store)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 760)

        MenuBarExtra("dev", systemImage: "waveform.path.ecg") {
            MenuBarSummaryView(store: appDelegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarSummaryView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        QuickSummaryView(store: store) { action in
            store.requestQuickAction(action)
            WorkspaceWindowActivation.show { openWindow(id: "workspace") }
        }
    }
}
