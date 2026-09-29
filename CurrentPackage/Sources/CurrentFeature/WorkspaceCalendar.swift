import SwiftUI

struct WorkspaceCalendar: View {
    @ObservedObject var controller: TimelineController
    @ObservedObject var workspace: WorkspaceViewState
    @State private var month: Date
    @State private var writtenDays: Set<String> = []
    private let calendar = Calendar.current
    private let streamID: UUID?
    private let libraryID: String

    init(controller: TimelineController, workspace: WorkspaceViewState) {
        self.controller = controller
        self.workspace = workspace
        self.streamID = controller.stream?.id
        self.libraryID = controller.store.libraryID
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: workspace.selectedDate)?.start ?? workspace.selectedDate)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                WorkspaceIconButton(title: "Previous month", symbol: "chevron.left") { changeMonth(-1) }
                WorkspaceIconButton(title: "Next month", symbol: "chevron.right") { changeMonth(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<7) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CurrentTheme.secondaryText)
                        .frame(height: 18)
                }
                ForEach(0..<leadingDays, id: \.self) { _ in Color.clear.frame(width: 32, height: 34) }
                ForEach(dates, id: \.self) { date in dayButton(date) }
            }
            HStack(spacing: 5) {
                Circle().fill(CurrentTheme.accent).frame(width: 3, height: 3)
                Text("Contains writing").font(.system(size: 11)).foregroundStyle(CurrentTheme.secondaryText)
                Spacer()
                Button("Today") { open(controller.today) }.buttonStyle(.plain)
            }
            Divider()
            HStack {
                DatePicker("Date", selection: $workspace.selectedDate, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field).controlSize(.small)
                Spacer()
                Button("Go") { open(workspace.selectedDate) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(CurrentTheme.pageBackground)
        .onAppear {
            month = calendar.dateInterval(of: .month, for: workspace.selectedDate)?.start ?? workspace.selectedDate
        }
        .task(id: "\(controller.store.libraryID)|\(controller.stream?.id.uuidString ?? "")|\(month.timeIntervalSinceReferenceDate)|\(controller.libraryContentRevision)") {
            writtenDays = controller.writtenDayKeys(inMonth: month)
        }
        .onChange(of: controller.days) { _, _ in writtenDays = controller.writtenDayKeys(inMonth: month) }
        .onChange(of: workspace.selectedDate) { _, date in
            month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }

    private var leadingDays: Int {
        (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
    }

    private var dates: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: workspace.selectedDate)
        let today = calendar.isDate(date, inSameDayAs: controller.today)
        let written = writtenDays.contains(DayFormatting.dayKey(for: date, calendar: calendar))
        return Button { open(date) } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: today ? .semibold : .regular))
                    .monospacedDigit()
                Circle().fill(written ? CurrentTheme.accent : .clear).frame(width: 3, height: 3)
            }
            .frame(width: 32, height: 34)
            .foregroundStyle(selected || today ? CurrentTheme.accent : CurrentTheme.primaryText)
            .background(selected ? CurrentTheme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(today ? CurrentTheme.accent.opacity(0.5) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(WorkspaceControlStyle())
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (written ? ", contains writing" : ", empty") + (today ? ", today" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func changeMonth(_ offset: Int) {
        month = calendar.date(byAdding: .month, value: offset, to: month) ?? month
    }

    private func open(_ date: Date) {
        let navigationID = controller.scrollRequest?.id
        workspace.selectedDate = date
        workspace.showsDatePicker = false
        // Closing the native popover restores its previous responder. Queue the
        // jump after that change, independently of SwiftUI's retained content.
        DispatchQueue.main.async {
            guard controller.store.libraryID == libraryID, controller.stream?.id == streamID,
                  controller.scrollRequest?.id == navigationID else { return }
            controller.jumpToDate(date)
        }
    }
}
