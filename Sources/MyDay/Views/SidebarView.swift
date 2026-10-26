import Foundation
import SwiftUI

public struct SidebarView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var totalDurationString: String {
        let total = appState.cards.reduce(0.0) { $0 + $1.duration }
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        return "\(h)ч \(m)м"
    }

    private func durationString(for duration: TimeInterval) -> String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        if h > 0 {
            return "\(h)ч \(m)м"
        } else {
            return "\(m)м"
        }
    }

    private var categoryBreakdown: [(category: ActivityCategory, duration: TimeInterval, percentage: Int)] {
        let total = max(1, appState.cards.reduce(0.0) { $0 + $1.duration })
        var map: [ActivityCategory: TimeInterval] = [:]
        for card in appState.cards {
            map[card.category, default: 0] += card.duration
        }
        return map.sorted(by: { $0.value > $1.value }).map {
            ($0.key, $0.value, Int(($0.value / total) * 100))
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Space for macOS traffic lights
            Spacer()
                .frame(height: 18)

            // Header: Brand & AI Pill
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)

                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("MyDay")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Activity Journal")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status Indicator
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.isRecording && !appState.isPaused ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)

                    Text(appState.isRecording && !appState.isPaused ? "LIVE" : "PAUSED")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(appState.isRecording && !appState.isPaused ? Color.green : Color.orange)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
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
            }

            // Custom Date Navigation Component
            DateNavigatorView(appState: appState)

            // Metrics Card with Glass Glow & Category Distribution Line
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.accentColor)

                    Text("СВОДКА ДНЯ")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.secondary)
                        .tracking(0.6)

                    Spacer()
                }

                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(totalDurationString)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.primary, Color.primary.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("Активное время")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(appState.cards.count)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)
                        Text("Блоков")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                // Micro Stacked Category Distribution Track
                if !categoryBreakdown.isEmpty {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(categoryBreakdown, id: \.category) { item in
                                let width = max(3, (geo.size.width - CGFloat(categoryBreakdown.count - 1) * 2) * CGFloat(Double(item.percentage) / 100.0))
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color(hex: item.category.colorHex))
                                    .frame(width: width, height: 4)
                            }
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )

            // Categories Breakdown
            if !categoryBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        Text("РАСПРЕДЕЛЕНИЕ ПО ТЕМАМ")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.secondary)
                            .tracking(0.6)
                    }

                    VStack(spacing: 8) {
                        ForEach(categoryBreakdown, id: \.category) { item in
                            VStack(spacing: 4) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: item.category.colorHex))
                                        .frame(width: 7, height: 7)

                                    Text(item.category.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary.opacity(0.9))
                                        .lineLimit(1)

                                    Spacer()

                                    Text(durationString(for: item.duration))
                                        .font(.system(size: 10, design: .rounded))
                                        .foregroundColor(.secondary.opacity(0.8))

                                    Text("\(item.percentage)%")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 30, alignment: .trailing)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.05))
                                            .frame(height: 3)

                                        Capsule()
                                            .fill(Color(hex: item.category.colorHex))
                                            .frame(width: max(3, geo.size.width * CGFloat(Double(item.percentage) / 100.0)), height: 3)
                                    }
                                }
                                .frame(height: 3)
                            }
                        }
                    }
                }
            }

            Spacer()

            Divider()
                .opacity(0.3)

            // Footer: Engine Mode Status & Settings Button
            HStack(spacing: 8) {
                if appState.settings.engineMode == .native {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 16, height: 16)

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Нативный режим")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Автономно · 0% CPU")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(appState.isLMStudioConnected ? Color.green.opacity(0.25) : Color.red.opacity(0.25))
                            .frame(width: 14, height: 14)

                        Circle()
                            .fill(appState.isLMStudioConnected ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.isLMStudioConnected ? "LM Studio Active" : "LM Studio Offline")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)

                        if appState.isLMStudioConnected {
                            Text(appState.settings.selectedModel)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("127.0.0.1:1234")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Button {
                    appState.isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Настройки MyDay")
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Color(NSColor.windowBackgroundColor).opacity(0.65)
                Rectangle().fill(.ultraThinMaterial)
            }
        )
    }
}
