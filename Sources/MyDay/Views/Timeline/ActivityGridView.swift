import Foundation
import SwiftUI

public struct ActivityGridView: View {
    let cards: [TimelineCard]
    let selectedDate: Date

    public init(cards: [TimelineCard], selectedDate: Date) {
        self.cards = cards
        self.selectedDate = selectedDate
    }

    private var activeHoursSummary: [Int: ActivityCategory] {
        var map: [Int: ActivityCategory] = [:]
        let calendar = Calendar.current
        for card in cards {
            let startHour = calendar.component(.hour, from: card.startTime)
            let endHour = calendar.component(.hour, from: card.endTime)
            for h in startHour...max(startHour, endHour) {
                if (0...23).contains(h) {
                    map[h] = card.category
                }
            }
        }
        return map
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("АКТИВНОСТЬ ПО ЧАСАМ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                let activeCount = activeHoursSummary.count
                Text("\(activeCount) ч активных")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // 24-Hour Grid Slots
            GeometryReader { geo in
                let slotWidth = (geo.size.width - CGFloat(23 * 4)) / 24.0

                HStack(spacing: 4) {
                    ForEach(0..<24, id: \.self) { hour in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(colorForHour(hour))
                                .frame(width: max(4, slotWidth), height: 18)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.white.opacity(activeHoursSummary[hour] != nil ? 0.2 : 0.04), lineWidth: 0.5)
                                )

                            if hour % 4 == 0 {
                                Text(String(format: "%02d", hour))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.secondary.opacity(0.8))
                            } else {
                                Spacer()
                                    .frame(height: 10)
                            }
                        }
                    }
                }
            }
            .frame(height: 32)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
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
    }

    private func colorForHour(_ hour: Int) -> Color {
        if let cat = activeHoursSummary[hour] {
            return Color(hex: cat.colorHex)
        }
        return Color.primary.opacity(0.06)
    }
}
