import Foundation
import SwiftUI

public struct ActivityCardView: View {
    let card: TimelineCard
    let isLast: Bool
    @ObservedObject var appState: AppState

    public init(card: TimelineCard, isLast: Bool = false, appState: AppState) {
        self.card = card
        self.isLast = isLast
        self.appState = appState
    }

    private var timeRangeString: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        let start = df.string(from: card.startTime)
        let end = df.string(from: card.endTime)
        let min = max(1, Int(card.duration / 60))
        return "\(start) – \(end) · \(min) мин"
    }

    private var categoryColor: Color {
        Color(hex: card.category.colorHex)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // MARK: - Left Timeline Rail
            VStack(spacing: 0) {
                // Glowing Node
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.25))
                        .frame(width: 18, height: 18)
                        .blur(radius: 2)

                    Circle()
                        .fill(categoryColor)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                        )
                }
                .padding(.top, 14)

                // Connector vertical line
                if !isLast {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [categoryColor.opacity(0.4), Color.primary.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                        .padding(.vertical, 2)
                }
            }
            .frame(width: 20)

            // MARK: - Main Card Content
            VStack(alignment: .leading, spacing: 12) {
                // Header: Category Pill, Time, AI Sparkle, Actions
                HStack(alignment: .center, spacing: 8) {
                    // Category Badge with Neon Glow
                    HStack(spacing: 5) {
                        Image(systemName: card.category.sfSymbol)
                            .font(.system(size: 10, weight: .bold))
                        Text(card.category.displayName)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(categoryColor.opacity(0.18))
                    .foregroundColor(categoryColor)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(categoryColor.opacity(0.35), lineWidth: 0.8)
                    )

                    // Time Range
                    Text(timeRangeString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    if card.isAIAnalyzed {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                            Text("AI")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(Color.purple)
                        .clipShape(Capsule())
                    }

                    Spacer()

                    // Quick Actions
                    Button {
                        appState.copyObsidianCard(card)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                            Text("Obsidian")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .foregroundColor(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Скопировать карточку в буфер для Obsidian")

                    Menu {
                        Button {
                            appState.copyObsidianCard(card)
                        } label: {
                            Label("Копировать Markdown", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button(role: .destructive) {
                            appState.deleteCard(card)
                        } label: {
                            Label("Удалить блок", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 18)
                }

                // Title & Narrative
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    if !card.summary.isEmpty {
                        Text(card.summary)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(2.5)
                    }
                }

                // Native App Icons Row with Usage Distribution
                if !card.appUsages.isEmpty {
                    appUsagesWithIconsView
                }

                // Cinematic Timelapse Scrubber & Preview
                TimelapseScrubberView(card: card, vm: appState.scrubberVM(for: card))

                // Tags Pill Row
                if !card.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(card.tags.prefix(5), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color.primary.opacity(0.05))
                                .foregroundColor(.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        }
    }

    private var appUsagesWithIconsView: some View {
        let total = max(1, card.appUsages.reduce(0.0) { $0 + $1.durationSeconds })
        let sorted = card.appUsages.sorted(by: { $0.durationSeconds > $1.durationSeconds })

        return HStack(spacing: 12) {
            ForEach(sorted.prefix(4)) { usage in
                let pct = Int((usage.durationSeconds / total) * 100)
                HStack(spacing: 5) {
                    AppIconView(bundleId: usage.bundleId, appName: usage.appName, size: 16)

                    Text(usage.appName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                    Text("\(pct)%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
