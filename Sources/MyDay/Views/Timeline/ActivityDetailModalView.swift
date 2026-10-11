import Foundation
import SwiftUI
import AppKit
import AVFoundation

public struct ActivityDetailModalView: View {
    let card: TimelineCard
    @ObservedObject var appState: AppState
    @ObservedObject var vm: ScrubberViewModel
    @Environment(\.dismiss) private var dismiss

    public init(card: TimelineCard, appState: AppState) {
        self.card = card
        self.appState = appState
        self.vm = appState.scrubberVM(for: card)
    }

    private var timeRangeString: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        let start = df.string(from: card.startTime)
        let end = df.string(from: card.endTime)
        return "\(start) – \(end) · \(card.durationFormatted)"
    }

    private var categoryColor: Color {
        Color(hex: card.category.colorHex)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack(alignment: .center, spacing: 12) {
                // Category Pill
                HStack(spacing: 5) {
                    Image(systemName: card.category.sfSymbol)
                        .font(.system(size: 11, weight: .bold))
                    Text(card.category.displayName)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(categoryColor.opacity(0.18))
                .foregroundColor(categoryColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(categoryColor.opacity(0.35), lineWidth: 0.8)
                )

                // Time Range
                Text(timeRangeString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                if card.isAIAnalyzed {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text("AI")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(Color.purple)
                    .clipShape(Capsule())
                }

                Spacer()

                // Copy for Obsidian
                Button {
                    appState.copyObsidianCard(card)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Obsidian")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Скопировать Markdown карточки")

                // Dismiss Button
                Button {
                    if vm.player != nil {
                        vm.closeVideoModal()
                    }
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - Scrollable Body
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Title
                    Text(card.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    // Interactive Media Stage
                    mediaStageView

                    // Scrubber Controls
                    scrubberControlsView

                    Divider()
                        .padding(.vertical, 4)

                    // Narrative Summary Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ОПИСАНИЕ АКТИВНОСТИ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)

                        if !card.summary.isEmpty {
                            Text(card.summary)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        } else {
                            Text("Автоматическое саммари отсутствует.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Applications Breakdown Section
                    if !card.appUsages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ИСПОЛЬЗОВАННЫЕ ПРИЛОЖЕНИЯ")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)

                            appUsagesListView
                        }
                    }

                    // Tags Section
                    if !card.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ТЕГИ")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 6) {
                                ForEach(card.tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3.5)
                                        .background(Color.primary.opacity(0.06))
                                        .foregroundColor(.secondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, idealWidth: 820, maxWidth: 940, minHeight: 580, idealHeight: 680, maxHeight: 820)
        .background(Color(NSColor.controlBackgroundColor))
        .task {
            vm.loadFrames(for: card)
        }
    }

    // MARK: - Media Stage View
    @ViewBuilder
    private var mediaStageView: some View {
        ZStack(alignment: .bottom) {
            if let player = vm.player {
                // Video Player Mode
                VStack(spacing: 0) {
                    NativePlayerView(player: player)
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    HStack {
                        Button {
                            vm.closeVideoModal()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.stack")
                                Text("Вернуться к скриншотам")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)

                        Spacer()
                    }
                }
            } else {
                // Interactive Frame Viewer Mode
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        ZStack {
                            if let nsImage = vm.currentImage {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if let kf = card.keyframePath, let nsImage = NSImage(contentsOfFile: kf) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay(
                                        VStack(spacing: 6) {
                                            Image(systemName: "photo")
                                                .font(.system(size: 28))
                                                .foregroundColor(.secondary)
                                            Text("Скриншоты не записаны")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Gradient bottom bar for readability
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.65)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Frame Count Badge
                        HStack {
                            if !vm.frames.isEmpty {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 6, height: 6)
                                    Text("Кадр \(vm.currentFrameIndex + 1) из \(vm.frames.count)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                            }

                            Spacer()

                            Text("Ведите курсором по экрану для перемотки")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(10)
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard !vm.frames.isEmpty, geo.size.width > 0 else { return }
                            let fraction = max(0.0, min(1.0, location.x / geo.size.width))
                            let targetIdx = Int(fraction * Double(vm.frames.count - 1))
                            if targetIdx != vm.currentFrameIndex {
                                vm.currentFrameIndex = targetIdx
                            }
                        case .ended:
                            break
                        }
                    }
                }
                .frame(height: 380)
            }
        }
    }

    // MARK: - Scrubber Controls View
    private var scrubberControlsView: some View {
        HStack(spacing: 12) {
            // Previous Frame Button
            Button {
                vm.stepFrame(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(vm.currentFrameIndex <= 0)
            .keyboardShortcut(.leftArrow, modifiers: [])

            // Interactive Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 6)

                    let total = max(1, vm.frames.count)
                    let progress = CGFloat(vm.currentFrameIndex + 1) / CGFloat(total)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, geo.size.width * progress), height: 6)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 4, x: 0, y: 0)
                }
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !vm.frames.isEmpty, geo.size.width > 0 else { return }
                            let fraction = max(0.0, min(1.0, value.location.x / geo.size.width))
                            let target = Int(fraction * Double(vm.frames.count - 1))
                            if target != vm.currentFrameIndex {
                                vm.currentFrameIndex = target
                            }
                        }
                )
            }
            .frame(height: 28)

            // Next Frame Button
            Button {
                vm.stepFrame(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(vm.currentFrameIndex >= vm.frames.count - 1)
            .keyboardShortcut(.rightArrow, modifiers: [])

            // Play Video Timelapse Button
            if vm.isGeneratingVideo {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("Сборка...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor)
                .clipShape(Capsule())
            } else {
                Button {
                    vm.playTimelapseVideo(for: card)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Таймлапс")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.accentColor, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - App Usages Breakdown
    private var appUsagesListView: some View {
        let total = max(1, card.appUsages.reduce(0.0) { $0 + $1.durationSeconds })
        let sorted = card.appUsages.sorted(by: { $0.durationSeconds > $1.durationSeconds })

        return VStack(spacing: 8) {
            ForEach(sorted) { usage in
                let pct = Int((usage.durationSeconds / total) * 100)
                let mins = max(1, Int(usage.durationSeconds / 60))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        AppIconView(bundleId: usage.bundleId, appName: usage.appName, size: 18)

                        Text(usage.appName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)

                        Spacer()

                        Text("\(mins) мин (\(pct)%)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if !usage.windowTitles.isEmpty {
                        Text(usage.windowTitles.prefix(3).joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .padding(.leading, 26)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
