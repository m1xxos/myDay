import Foundation
import SwiftUI
import AppKit

public struct MainView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Fixed Left Sidebar (260px) - completely immune to breaking or accidental resizing
            SidebarView(appState: appState)
                .frame(width: 260)
                .fixedSize(horizontal: true, vertical: false)

            // Subtle vertical 1px divider spanning full window height
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .ignoresSafeArea()

            // Main Detail Timeline Feed
            ZStack(alignment: .bottom) {
                TimelineFeedView(appState: appState)

                // Floating Glassmorphism Toast Notification
                if let toast = appState.toastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 12, weight: .bold))

                        Text(toast)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThickMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 5)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: appState.toastMessage)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            // Right Activity Inspector Panel (Dayflow Style)
            if appState.isInspectorVisible {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                    .ignoresSafeArea()

                ActivityInspectorView(appState: appState)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: appState.isInspectorVisible)
        .background(WindowAccessor { window in
            window.title = "MyDay — Автоматический журнал дня"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        })
        .sheet(isPresented: $appState.isShowingSettings) {
            SettingsView(appState: appState)
        }
        .sheet(isPresented: $appState.isShowingDaySummary) {
            DaySummaryView(appState: appState)
        }
        .sheet(isPresented: $appState.isShowingCinemaModal) {
            if let card = appState.cinemaCard ?? appState.selectedCard {
                TimelapseCinemaModalView(card: card, appState: appState)
            }
        }
        .onAppear {
            checkPermissions()
        }
    }

    private func checkPermissions() {
        if !ScreenCaptureManager.shared.checkPermission() {
            ScreenCaptureManager.shared.requestPermission()
        }
    }
}

// AppKit Window Accessor to style the window titlebar & enable background drag
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            onWindow(window)
        }
    }
}
