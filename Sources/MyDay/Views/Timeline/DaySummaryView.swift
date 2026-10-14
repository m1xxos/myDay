import Foundation
import SwiftUI
import AVFoundation
import AppKit

public struct DonutChartView: View {
    let stats: [DayCategoryStat]
    let totalDurationFormatted: String

    public init(stats: [DayCategoryStat], totalDurationFormatted: String) {
        self.stats = stats
        self.totalDurationFormatted = totalDurationFormatted
    }

    private struct Segment: Identifiable {
        var id: ActivityCategory { category }
        let category: ActivityCategory
        let startFraction: CGFloat
        let endFraction: CGFloat
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var current: CGFloat = 0
        for stat in stats {
            let fraction = CGFloat(stat.percentage / 100.0)
            guard fraction > 0.005 else { continue }
            result.append(Segment(category: stat.category, startFraction: current, endFraction: current + fraction))
            current += fraction
        }
        return result
    }

    public var body: some View {
        ZStack {
            if segments.isEmpty {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 18)
            } else {
                ForEach(segments) { seg in
                    Circle()
                        .trim(from: seg.startFraction, to: seg.endFraction)
                        .stroke(
                            Color(hex: seg.category.colorHex),
                            style: StrokeStyle(lineWidth: 18, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }

            VStack(spacing: 2) {
                Text(totalDurationFormatted)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("активности")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 140, height: 140)
        .padding(.vertical, 8)
    }
}

public struct DaySummaryView: View {
    @ObservedObject var appState: AppState
    @StateObject private var vm = DaySummaryViewModel()

    public init(appState: AppState) {
        self.appState = appState
    }

    private var formattedDate: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMMM yyyy"
        return df.string(from: appState.selectedDate)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.accentColor)

                    Text("Итоги дня")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)

                    Text("·")
                        .foregroundColor(.secondary.opacity(0.4))

                    Text(formattedDate)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.down.right.fill")
                            .font(.system(size: 10))
                        Text("\(vm.totalCardsCount) блоков")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .foregroundColor(.secondary)

                    if vm.totalVideoFrames > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 10))
                            Text("\(vm.totalVideoFrames) кадров")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .foregroundColor(.secondary)
                    }

                    Button {
                        appState.isShowingDaySummary = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Main Stage: Large Video Stage (Left) & Rich Stats Sidebar (Right)
            HStack(spacing: 0) {
                // Large Video Player Stage
                ZStack {
                    Color.black.ignoresSafeArea()

                    if let player = vm.videoPlayer {
                        NativePlayerView(player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if vm.isGeneratingVideo {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Сборка 60fps таймлапса дня...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            if vm.totalVideoFrames > 0 {
                                Text("Объединяю \(vm.totalVideoFrames) кадров в единый фильм")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "film")
                                .font(.system(size: 38))
                                .foregroundColor(.white.opacity(0.25))
                            Text("Нет сохраненных кадров за этот день")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                // Stats & Donut Sidebar
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Section: Categories & Donut
                        VStack(alignment: .leading, spacing: 12) {
                            Text("РАСПРЕДЕЛЕНИЕ ВРЕМЕНИ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(0.5)

                            // Donut Chart
                            HStack {
                                Spacer()
                                DonutChartView(
                                    stats: vm.categoryStats,
                                    totalDurationFormatted: DaySummaryViewModel.formatDuration(vm.totalDuration)
                                )
                                Spacer()
                            }

                            // Category Legend
                            VStack(spacing: 6) {
                                ForEach(vm.categoryStats) { stat in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(hex: stat.category.colorHex))
                                            .frame(width: 8, height: 8)

                                        Image(systemName: stat.category.sfSymbol)
                                            .font(.system(size: 10))
                                            .foregroundColor(Color(hex: stat.category.colorHex))
                                            .frame(width: 14)

                                        Text(stat.category.displayName)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)

                                        Spacer()

                                        Text("\(Int(round(stat.percentage)))%")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.secondary)

                                        Text(DaySummaryViewModel.formatDuration(stat.duration))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        Divider()
                            .overlay(Color.white.opacity(0.06))

                        // Section: Unfinished Tasks
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "checklist")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.orange)

                                    Text("НЕЗАВЕРШЕННЫЕ ДЕЛА")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .tracking(0.5)
                                }

                                Spacer()

                                if vm.isLoadingTasks {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                        Text("Поиск...")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                } else if !vm.unfinishedTasks.isEmpty {
                                    let remainingCount = vm.unfinishedTasks.filter { !$0.isCompleted }.count
                                    Text("\(remainingCount) из \(vm.unfinishedTasks.count)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(Capsule())

                                    // Copy checklist button
                                    Button {
                                        vm.copyTasksToMarkdown(date: appState.selectedDate)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: vm.copySuccessToast ? "checkmark" : "doc.on.doc")
                                                .font(.system(size: 9))
                                            Text(vm.copySuccessToast ? "Скопировано!" : "Скопировать")
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .foregroundColor(vm.copySuccessToast ? .green : .secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Скопировать чеклист в Markdown для Obsidian, Things или Todoist")
                                }
                            }

                            if vm.unfinishedTasks.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green.opacity(0.8))
                                        .font(.system(size: 14))
                                    Text("Все начатые дела за день завершены 👍")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 6)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(vm.unfinishedTasks) { task in
                                        UnfinishedTaskRowView(task: task) {
                                            vm.toggleTaskCompletion(id: task.id)
                                        }
                                    }
                                }
                            }
                        }

                        Divider()
                            .overlay(Color.white.opacity(0.06))

                        // Section: Top Apps
                        if !vm.topApps.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("ТОП ПРИЛОЖЕНИЙ")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .tracking(0.5)

                                ForEach(vm.topApps.prefix(5)) { app in
                                    VStack(spacing: 4) {
                                        HStack(spacing: 8) {
                                            AppIconView(bundleId: app.bundleId, appName: app.appName, size: 16)

                                            Text(app.appName)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.primary)

                                            Spacer()

                                            Text("\(Int(round(app.percentage)))%")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.secondary)

                                            Text(DaySummaryViewModel.formatDuration(app.duration))
                                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }

                                        // Usage bar
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color.white.opacity(0.05))
                                                    .frame(height: 4)
                                                Capsule()
                                                    .fill(Color.accentColor.opacity(0.75))
                                                    .frame(width: max(4, geo.size.width * CGFloat(app.percentage / 100.0)), height: 4)
                                            }
                                        }
                                        .frame(height: 4)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(width: 380)
                .background(
                    ZStack {
                        Color(NSColor.windowBackgroundColor).opacity(0.6)
                        Rectangle().fill(.ultraThinMaterial)
                    }
                )
            }
        }
        .frame(minWidth: 1040, idealWidth: 1120, maxWidth: 1300, minHeight: 640, idealHeight: 700, maxHeight: 850)
        .onAppear {
            vm.loadSummary(cards: appState.cards, date: appState.selectedDate, appState: appState)
        }
        .onDisappear {
            vm.cleanup()
        }
    }
}

public struct UnfinishedTaskRowView: View {
    let task: UnfinishedTask
    let onToggle: () -> Void

    public init(task: UnfinishedTask, onToggle: @escaping () -> Void) {
        self.task = task
        self.onToggle = onToggle
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Checkbox button
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(task.isCompleted ? .green : .secondary.opacity(0.7))
            }
            .buttonStyle(.plain)

            // Task title
            Text(task.title)
                .font(.system(size: 12, weight: task.isCompleted ? .regular : .medium))
                .strikethrough(task.isCompleted)
                .foregroundColor(task.isCompleted ? .secondary.opacity(0.6) : .primary)
                .lineLimit(2)

            Spacer()

            // App icon & subtle name badge
            HStack(spacing: 4) {
                AppIconView(appName: task.appName, size: 12)
                Text(task.appName)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(task.isCompleted ? Color.white.opacity(0.02) : Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(task.isCompleted ? Color.white.opacity(0.03) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

