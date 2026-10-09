import Foundation
import SwiftUI
import AppKit

@MainActor
public final class DateNavigatorViewModel: ObservableObject {
    @Published public var isPopoverOpen: Bool = false
    @Published public var displayedMonth: Date = Date()
    @Published public var activeDaysInMonth: Set<Int> = []

    private let calendar = Calendar.current

    public init() {
        self.displayedMonth = Date()
        refreshActiveDays()
    }

    public func refreshActiveDays() {
        self.activeDaysInMonth = DatabaseManager.shared.fetchActiveDays(inMonth: displayedMonth)
    }

    public func shiftDay(by delta: Int, appState: AppState) {
        if let next = calendar.date(byAdding: .day, value: delta, to: appState.selectedDate) {
            appState.loadCards(for: next)
            self.displayedMonth = next
            refreshActiveDays()
        }
    }

    public func shiftMonth(by delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            self.displayedMonth = next
            refreshActiveDays()
        }
    }

    public func selectDate(_ date: Date, appState: AppState) {
        appState.loadCards(for: date)
        self.displayedMonth = date
        self.isPopoverOpen = false
        refreshActiveDays()
    }

    public func jumpToToday(appState: AppState) {
        let today = Date()
        appState.loadCards(for: today)
        self.displayedMonth = today
        self.isPopoverOpen = false
        refreshActiveDays()
    }

    public func formattedDateLabel(for date: Date) -> (prefix: String, text: String) {
        if calendar.isDateInToday(date) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "d MMM"
            return ("Сегодня", df.string(from: date))
        } else if calendar.isDateInYesterday(date) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "d MMM"
            return ("Вчера", df.string(from: date))
        } else if calendar.isDateInTomorrow(date) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "d MMM"
            return ("Завтра", df.string(from: date))
        } else {
            let prefixDf = DateFormatter()
            prefixDf.locale = Locale(identifier: "ru_RU")
            prefixDf.dateFormat = "EEE"
            let textDf = DateFormatter()
            textDf.locale = Locale(identifier: "ru_RU")
            textDf.dateFormat = "d MMM"
            return (prefixDf.string(from: date).capitalized, textDf.string(from: date))
        }
    }

    public func monthTitle(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date).capitalized
    }

    public struct DaySlot: Identifiable {
        public let id = UUID()
        public let date: Date
        public let dayNumber: Int
        public let isCurrentMonth: Bool
        public let isToday: Bool
        public let isSelected: Bool
        public let hasActivity: Bool
    }

    public func generateDaysGrid(selectedDate: Date) -> [DaySlot] {
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: startOfMonth)
        let offset = (weekday + 5) % 7 // Monday = 0 offset

        guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: startOfMonth) else {
            return []
        }

        var slots: [DaySlot] = []
        let currentMonthComponent = calendar.component(.month, from: displayedMonth)

        for i in 0..<42 {
            guard let slotDate = calendar.date(byAdding: .day, value: i, to: gridStart) else { continue }
            let slotMonth = calendar.component(.month, from: slotDate)
            let dayNumber = calendar.component(.day, from: slotDate)
            let isCurrentMonth = slotMonth == currentMonthComponent
            let isToday = calendar.isDateInToday(slotDate)
            let isSelected = calendar.isDate(slotDate, inSameDayAs: selectedDate)
            let hasActivity = isCurrentMonth && activeDaysInMonth.contains(dayNumber)

            slots.append(DaySlot(
                date: slotDate,
                dayNumber: dayNumber,
                isCurrentMonth: isCurrentMonth,
                isToday: isToday,
                isSelected: isSelected,
                hasActivity: hasActivity
            ))
        }

        return slots
    }
}

public struct DateNavigatorView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var vm: DateNavigatorViewModel

    public init(appState: AppState, vm: DateNavigatorViewModel = DateNavigatorViewModel()) {
        self.appState = appState
        self.vm = vm
    }

    public var body: some View {
        HStack(spacing: 5) {
            // Previous Day Button
            Button {
                vm.shiftDay(by: -1, appState: appState)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Предыдущий день")

            // Main Interactive Date Pill (Triggers Popover)
            Button {
                vm.displayedMonth = appState.selectedDate
                vm.refreshActiveDays()
                vm.isPopoverOpen.toggle()
            } label: {
                let formatted = vm.formattedDateLabel(for: appState.selectedDate)
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)

                    HStack(spacing: 4) {
                        Text(formatted.prefix)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)

                        Text(formatted.text)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            vm.isPopoverOpen
                                ? Color.accentColor.opacity(0.5)
                                : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $vm.isPopoverOpen, arrowEdge: .bottom) {
                datePopoverContent
            }

            // Next Day Button
            Button {
                vm.shiftDay(by: 1, appState: appState)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Следующий день")

            Spacer()

            // Jump to Today Pill if not currently on today
            if !Calendar.current.isDateInToday(appState.selectedDate) {
                Button {
                    vm.jumpToToday(appState: appState)
                } label: {
                    Text("Сегодня")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onAppear {
            vm.refreshActiveDays()
        }
    }

    // MARK: - Sleek Popover Calendar

    private var datePopoverContent: some View {
        VStack(spacing: 12) {
            // Quick Jump Chips
            HStack(spacing: 6) {
                quickChip(title: "Сегодня") {
                    vm.jumpToToday(appState: appState)
                }
                quickChip(title: "Вчера") {
                    if let y = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
                        vm.selectDate(y, appState: appState)
                    }
                }
                quickChip(title: "-7 дней") {
                    if let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) {
                        vm.selectDate(weekAgo, appState: appState)
                    }
                }
                Spacer()
            }

            Divider()
                .opacity(0.4)

            // Month Navigator Header
            HStack {
                Button {
                    vm.shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(vm.monthTitle(for: vm.displayedMonth))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    vm.shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Weekdays Header
            let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Month Days Grid
            let slots = vm.generateDaysGrid(selectedDate: appState.selectedDate)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(slots) { slot in
                    dayCellView(slot: slot)
                }
            }
        }
        .padding(14)
        .frame(width: 270)
        .background(.ultraThickMaterial)
    }

    private func quickChip(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func dayCellView(slot: DateNavigatorViewModel.DaySlot) -> some View {
        Button {
            vm.selectDate(slot.date, appState: appState)
        } label: {
            VStack(spacing: 2) {
                Text("\(slot.dayNumber)")
                    .font(.system(size: 11, weight: slot.isSelected ? .bold : .medium))
                    .foregroundColor(
                        slot.isSelected
                            ? .white
                            : (slot.isCurrentMonth ? (slot.isToday ? .accentColor : .primary) : .secondary.opacity(0.3))
                    )

                // Activity dot indicator
                if slot.hasActivity {
                    Circle()
                        .fill(slot.isSelected ? Color.white : Color.accentColor)
                        .frame(width: 3.5, height: 3.5)
                } else {
                    Spacer()
                        .frame(height: 3.5)
                }
            }
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if slot.isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 4, x: 0, y: 1)
                    } else if slot.isToday {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                    } else {
                        Color.clear
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}
