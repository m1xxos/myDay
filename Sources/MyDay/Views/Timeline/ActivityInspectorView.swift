import Foundation
import SwiftUI
import AppKit

public struct ActivityInspectorView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var timeRangeString: String {
        guard let card = appState.selectedCard else { return "" }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        let start = df.string(from: card.startTime)
        let end = df.string(from: card.endTime)
        return "\(start) – \(end) · \(card.durationFormatted)"
    }

    private var categoryColor: Color {
        guard let card = appState.selectedCard else { return .accentColor }
        return Color(hex: card.category.colorHex)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let card = appState.selectedCard {
                cardDetailContent(card: card)
            } else {
                emptySelectionView
            }
        }
        .frame(width: 360)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Color(NSColor.windowBackgroundColor).opacity(0.5)
                Rectangle().fill(.ultraThinMaterial)
            }
        )
    }

    // MARK: - Selected Card Content
    private func cardDetailContent(card: TimelineCard) -> some View {
        let vm = appState.scrubberVM(for: card)

        return VStack(spacing: 0) {
            // Inspector Header
            HStack(alignment: .center, spacing: 8) {
                // Category Pill
                HStack(spacing: 5) {
                    Image(systemName: card.category.sfSymbol)
                        .font(.system(size: 10, weight: .bold))
                    Text(card.category.displayName)
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(categoryColor.opacity(0.18))
                .foregroundColor(categoryColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(categoryColor.opacity(0.3), lineWidth: 0.8)
                )

                if card.isAIAnalyzed {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text("AI")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(Color.purple)
                    .clipShape(Capsule())
                }

                Spacer()

                // Copy Obsidian
                Button {
                    appState.copyObsidianCard(card)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Скопировать Markdown карточки")

                // Delete Card Menu
                Menu {
                    Button(role: .destructive) {
                        appState.deleteCard(card)
                    } label: {
                        Label("Удалить активность", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(5)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)

                // Close Inspector
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.isInspectorVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Закрыть панель деталей")
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 12)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Scrollable Details
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title & Time Range
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(3)

                        Text(timeRangeString)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    // Hero Media Preview with Live Scrubber & Cinema Opener
                    heroMediaPreview(card: card, vm: vm)

                    // Narrative Summary Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ОПИСАНИЕ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)

                        let cleanSummary = sanitizeSummaryText(card.summary)
                        if !cleanSummary.isEmpty {
                            Text(cleanSummary)
                                .font(.system(size: 13))
                                .foregroundColor(.primary.opacity(0.9))
                                .lineSpacing(3.5)
                                .textSelection(.enabled)
                        } else {
                            Text("Автоматическое описание не сформировано.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Applications Breakdown Section
                    if !card.appUsages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ПРИЛОЖЕНИЯ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(0.5)

                            appUsagesView(card: card)
                        }
                    }

                    // Tags Section
                    let validTags = card.cleanedTags
                    if !validTags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ТЕГИ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(0.5)

                            tagsFlowView(tags: validTags)
                        }
                    }
                }
                .padding(16)
            }
        }
        .task(id: card.id) {
            vm.loadFrames(for: card)
        }
    }

    // MARK: - Hero Media Preview (16:9 / 16:10 Native Ratio)
    private func heroMediaPreview(card: TimelineCard, vm: ScrubberViewModel) -> some View {
        Button {
            appState.openCinemaPlayer(for: card)
        } label: {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // Background Image Frame
                    ZStack {
                        if let nsImage = vm.currentImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else if let kf = card.keyframePath, let nsImage = NSImage(contentsOfFile: kf) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.black.opacity(0.4))
                                .overlay(
                                    VStack(spacing: 4) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 20))
                                            .foregroundColor(.secondary)
                                        Text("Нет кадров")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                )
                        }
                    }

                    // Vignette gradient
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.75)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    // Center Glassmorphic Play Button
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                            Text("Смотреть таймлапс")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 2)
                        Spacer()
                    }

                    // Bottom Info Bar
                    HStack {
                        if !vm.frames.isEmpty {
                            Text("Кадр \(vm.currentFrameIndex + 1) / \(vm.frames.count)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(4)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .contentShape(Rectangle())
                // Hover scrubber: preview moves live under cursor
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
            .frame(height: 195)
        }
        .buttonStyle(.plain)
        .help("Нажмите для открытия полноэкранного плеера таймлапса")
    }

    // MARK: - Applications Breakdown List
    private func appUsagesView(card: TimelineCard) -> some View {
        let total = max(1, card.appUsages.reduce(0.0) { $0 + $1.durationSeconds })
        let sorted = card.appUsages.sorted(by: { $0.durationSeconds > $1.durationSeconds })

        return VStack(spacing: 6) {
            ForEach(sorted.prefix(5)) { usage in
                let pct = Int((usage.durationSeconds / total) * 100)
                let mins = max(1, Int(usage.durationSeconds / 60))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        AppIconView(bundleId: usage.bundleId, appName: usage.appName, size: 16)

                        Text(usage.appName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)

                        Spacer()

                        Text("\(mins) мин · \(pct)%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    // Cleaned-up window title (sanitized)
                    if let rawTitle = usage.windowTitles.first {
                        let clean = TimelineCard.cleanWindowTitle(rawTitle, appName: usage.appName)
                        if !clean.isEmpty {
                            Text(clean)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.75))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.leading, 23)
                        }
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    // MARK: - Clean Tags Flow
    private func tagsFlowView(tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(tags.prefix(6), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .foregroundColor(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }

    // MARK: - Empty Selection View
    private var emptySelectionView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sidebar.right")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("Выберите активность")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Нажмите на карточку в ленте для просмотра подробностей и таймлапса")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Strip redundant "Активность: " or "Деятельность: " prefixes
    private func sanitizeSummaryText(_ text: String) -> String {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.starts(with: "Активность: ") {
            clean = String(clean.dropFirst("Активность: ".count))
        } else if clean.starts(with: "Деятельность: ") {
            clean = String(clean.dropFirst("Деятельность: ".count))
        }
        return clean
    }
}
