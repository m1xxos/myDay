import Foundation
import SwiftUI
import AppKit

@main
struct MyDayApp: App {
    @StateObject private var appState = AppState.shared
    @Environment(\.openWindow) private var openWindow

    init() {
        // Ensure regular macOS app behavior (Dock icon, menu bar)
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup(id: "mainWindow") {
            MainView(appState: appState)
                .frame(minWidth: 840, minHeight: 540)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarView(appState: appState) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "mainWindow")
            }
        } label: {
            Image(systemName: appState.isRecording && !appState.isPaused ? "circle.circle.fill" : "pause.circle.fill")
        }
    }
}
