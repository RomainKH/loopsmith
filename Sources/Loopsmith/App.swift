#if os(macOS)
import AppKit
import SwiftUI

/// The macOS window app. `Entry` starts it when the binary gets no CLI command.
struct LoopsmithApp: App {
    @State private var store = AppStore()

    init() {
        // Started with `swift run` (no app bundle), the process would get no Dock icon nor focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.applicationIconImage = Brand.makeAppIcon()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Loopsmith") {
            ContentView()
                .environment(store)
                .tint(Brand.cobalt)
                .frame(minWidth: 1020, minHeight: 660)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.stopAll()
                }
        }
        SwiftUI.Settings {
            SettingsView()
                .environment(store)
                .tint(Brand.cobalt)
        }
    }
}

#endif
