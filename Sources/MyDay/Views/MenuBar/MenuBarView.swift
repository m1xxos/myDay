import Foundation
import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var appState: AppState
    let onOpenMainWindow: () -> Void

    public init(appState: AppState, onOpenMainWindow: @escaping () -> Void) {
        self.appState = appState
        self.onOpenMainWindow = onOpenMainWindow
    }

    private var totalDurationString: String {
        let total = appState.cards.reduce(0.0) { $0 + $1.duration }
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        return "\(h)ч \(m)м"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header status
            HStack(spacing: 8) {
                let isPrivate = appState.settings.excludePrivateBrowsing && (appState.currentWindowContext?.isPrivateBrowsing == true)
                let isCapturing = appState.isRecording && !appState.isPaused && !isPrivate

                Circle()
                    .fill(isCapturing ? Color.green : (isPrivate ? Color.purple : Color.orange))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    if isPrivate {
                        Text("MyDay: Приватный режим")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.purple)
                    } else {
                        Text(appState.isPaused ? "Запись на паузе" : "MyDay: \(appState.currentWindowContext?.appName ?? "Активен")")
                            .font(.system(size: 12, weight: .semibold))
                    }

                    Text(isPrivate ? "Запись экрана приостановлена" : "Сегодня: \(totalDurationString) · \(appState.cards.count) блоков")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            Divider()

            // Quick Actions
            Button {
                appState.copyObsidianDay()
            } label: {
                Label("Скопировать день в Obsidian", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await appState.triggerBatchAnalysis()
                }
            } label: {
                Label("Собрать блок активности сейчас", systemImage: "sparkles")
            }
            .buttonStyle(.plain)

            Button {
                appState.togglePause()
            } label: {
                Label(appState.isPaused ? "Возобновить запись" : "Приостановить запись", systemImage: appState.isPaused ? "play" : "pause")
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                onOpenMainWindow()
            } label: {
                Label("Открыть журнал MyDay", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Выход из MyDay", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 250)
    }
}
