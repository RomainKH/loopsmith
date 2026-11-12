import AppKit
import SwiftUI

@main
struct LoopsmithApp: App {
    @State private var store = AppStore()

    init() {
        // Started with `swift run` (no app bundle), the process would get no Dock icon nor focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Loopsmith") {
            ContentView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 620)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.stopAll()
                }
        }
        SwiftUI.Settings {
            SettingsView().environment(store)
        }
    }
}
