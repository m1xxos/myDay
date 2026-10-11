import Foundation
import SwiftUI
import AppKit

public struct TimelineFeedView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Header Bar - perfectly aligned with Sidebar brand header
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .background(
                    ZStack {
                        Color(NSColor.windowBackgroundColor).opacity(0.4)
                        Rectangle().fill(.ultraThinMaterial)
                    }
                )
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.white.opacity(0.08)),
                    alignment: .bottom
                )

            // Screen Recording Permission Banner (if missing, displayed cleanly under headerBar)
            if !appState.hasScreenPermission {
                permissionNoticeBanner
            }

            // Timeline Content
            ScrollView {
                VStack(spacing: 18) {
                    // Top 24-Hour Activity Bar
                    ActivityGridView(cards: appState.cards, selectedDate: appState.selectedDate)
                        .padding(.top, 4)

                    // Feed Cards or Empty State
                    if appState.cards.isEmpty {
                        emptyStateView
                    } else {
                        LazyVStack(spacing: 14) {
                            let reversedCards = Array(appState.cards.reversed())
                            ForEach(Array(reversedCards.enumerated()), id: \.element.id) { index, card in
                                ActivityCardView(
                                    card: card,
                                    isLast: index == reversedCards.count - 1,
                                    appState: appState
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            checkPermissionState()
        }
    }

    private var permissionNoticeBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 2) {
                Text("Требуется разрешение на запись экрана")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Без разрешения невозможно делать снимки и таймлапс. Включите MyDay в Системных настройках.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    openScreenRecordingSettings()
                } label: {
                    Text("Настройки")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    appState.relaunchApp()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("Перезапустить")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Перезапустить приложение для применения системных разрешений")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.08))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.orange.opacity(0.2)),
            alignment: .bottom
        )
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Live Status Capsule
            HStack(spacing: 8) {
                // Pulse Dot & LIVE Badge
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(appState.isRecording && !appState.isPaused ? Color.green.opacity(0.3) : Color.orange.opacity(0.3))
                            .frame(width: 14, height: 14)

                        Circle()
                            .fill(appState.isRecording && !appState.isPaused ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                    }

                    Text(appState.isRecording && !appState.isPaused ? "LIVE" : "PAUSED")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(appState.isRecording && !appState.isPaused ? Color.green : Color.orange)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    (appState.isRecording && !appState.isPaused ? Color.green : Color.orange).opacity(0.12)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            (appState.isRecording && !appState.isPaused ? Color.green : Color.orange).opacity(0.25),
                            lineWidth: 1
                        )
                )

                // Current Active Window Pill
                if appState.isRecording && !appState.isPaused {
                    if let current = appState.currentWindowContext {
                        HStack(spacing: 6) {
                            AppIconView(bundleId: current.bundleId, appName: current.appName, size: 16)

                            Text(current.appName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)

                            if !current.windowTitle.isEmpty && current.windowTitle != current.appName {
                                let cleanTitle = TimelineCard.cleanWindowTitle(current.windowTitle, appName: current.appName)
                                if !cleanTitle.isEmpty && cleanTitle != current.appName {
                                    Text("–")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary.opacity(0.4))

                                    Text(cleanTitle)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: 110, alignment: .leading)
                                }
                            }

                            if appState.lastDiffPercent > 0 {
                                Text("· \(String(format: "%.1f", appState.lastDiffPercent))% diff")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.8))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        )
                    }
                } else {
                    Text("Запись приостановлена")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .layoutPriority(0)

            Spacer()

            // Action Buttons
            HStack(spacing: 6) {
                // Pause / Resume Toggle
                Button {
                    appState.togglePause()
                } label: {
                    Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(appState.isPaused ? .green : .secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(appState.isPaused ? "Возобновить запись" : "Приостановить запись")

                // Analyze Now ("Собрать блок")
                Button {
                    Task {
                        await appState.triggerBatchAnalysis()
                    }
                } label: {
                    if appState.isAnalyzing {
                        HStack(spacing: 5) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                            Text("Анализ...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                        )
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.accentColor)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                            )
                    }
                }
                .buttonStyle(.plain)
                .help("Собрать накопленные снимки в AI-блок")

                // Consolidate fragmented sessions button ("Склеить дубли")
                Button {
                    appState.consolidateFragmentedCards()
                } label: {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Склеить дублирующиеся активности за день")

                // Day Summary ("Итоги дня")
                Button {
                    appState.isShowingDaySummary = true
                } label: {
                    Image(systemName: "film")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Открыть итоги дня и видео-таймлапс")

                // Export Obsidian ("В Obsidian")
                Button {
                    appState.copyObsidianDay()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("В Obsidian")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .help("Скопировать журнал дня в буфер обмена для Obsidian")

                // Inspector Toggle Button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.isInspectorVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(appState.isInspectorVisible ? .primary : .secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(appState.isInspectorVisible ? 0.09 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(appState.isInspectorVisible ? "Скрыть панель деталей" : "Показать панель деталей")
            }
            .layoutPriority(1)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 40)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 34))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 6) {
                Text("Таймлайн активности готов")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Мониторинг экрана и активных приложений уже запущен.\nНажмите кнопку ниже, чтобы мгновенно создать первый блок!")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 380)
            }

            Button {
                Task {
                    await appState.triggerBatchAnalysis()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Создать первый блок прямо сейчас")
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func checkPermissionState() {
        appState.checkPermissions()
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
