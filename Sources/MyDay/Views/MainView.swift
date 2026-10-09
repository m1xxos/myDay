import Foundation
import SwiftUI

public struct MainView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
        } detail: {
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
        }
        .sheet(isPresented: $appState.isShowingSettings) {
            SettingsView(appState: appState)
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
