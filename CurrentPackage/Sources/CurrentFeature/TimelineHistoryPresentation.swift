import Foundation
import CoreGraphics

struct TimelineEmptyDayGroup: Equatable {
    var days: [DayDocument]
    var isExpanded = false
    var id: String { "empty-days|\(days[0].id)|\(days[days.count - 1].dayKey)" }
}

enum TimelineHistoryPresentation {
    static let emptyGroupHeight: CGFloat = 30

    static func rows(days: [DayDocument], today: Date, activeDayID: String?, requestedDayID: String?,
                     expandedEmptyDayIDs: Set<String>, calendar: Calendar = .current) -> [TimelineCollectionItem] {
        var rows: [TimelineCollectionItem] = []
        var run: [DayDocument] = []
        func finishRun() {
            guard !run.isEmpty else { return }
            let expanded = run.contains { expandedEmptyDayIDs.contains($0.id) }
            rows.append(.emptyDays(TimelineEmptyDayGroup(days: run, isExpanded: expanded)))
            if expanded { rows.append(contentsOf: run.map(TimelineCollectionItem.day)) }
            run = []
        }
        for day in days {
            let empty = !day.isDirty && day.id != activeDayID && day.id != requestedDayID
                && !calendar.isDate(day.date, inSameDayAs: today)
                && !day.text.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
            if empty {
                if let previous = run.last,
                   previous.streamID != day.streamID || previous.libraryID != day.libraryID
                    || !calendar.isDate(day.date, inSameDayAs: calendar.addingDays(-1, to: previous.date)) {
                    finishRun()
                }
                run.append(day)
            } else {
                finishRun()
                rows.append(.day(day))
            }
        }
        finishRun()
        return rows
    }
}

/// Controller spacers use individual day heights. Retain the difference for
/// grouped empty days while they are outside the window, and remove it when
/// those days return. The visible anchor is restored after each structural edit.
struct TimelineEmptyDaySpacerLedger {
    private struct Adjustment { var date: Date; var height: CGFloat }
    private var libraries: [String: [String: Adjustment]] = [:]

    mutating func heights(previous: [TimelineCollectionItem], days: [DayDocument],
                          top: CGFloat, bottom: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        guard let newest = days.first, let oldest = days.last else { return (top, bottom) }
        let namespace = "\(newest.libraryID)|\(newest.streamID)"
        if top == 0 && bottom == 0 { libraries[namespace] = [:]; return (0, 0) }
        var adjustments = libraries[namespace] ?? [:]
        let retained = Set(days.map(\.id))
        for id in retained { adjustments.removeValue(forKey: id) }
        for case .emptyDays(let group) in previous {
            let difference = TimelineHistoryPresentation.emptyGroupHeight / CGFloat(group.days.count)
                - (group.isExpanded ? 0 : TimelineRowHeightCalculator.collapsedEmptyDayHeight)
            for day in group.days where !retained.contains(day.id)
                && day.libraryID == newest.libraryID && day.streamID == newest.streamID
                && (day.date > newest.date || day.date < oldest.date) {
                adjustments[day.id] = Adjustment(date: day.date, height: difference)
            }
        }
        libraries[namespace] = adjustments
        let topDifference = adjustments.values.filter { $0.date > newest.date }.reduce(CGFloat(0)) { $0 + $1.height }
        let bottomDifference = adjustments.values.filter { $0.date < oldest.date }.reduce(CGFloat(0)) { $0 + $1.height }
        return (max(0, top + topDifference), max(0, bottom + bottomDifference))
    }
}
