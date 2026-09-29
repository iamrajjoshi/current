import Foundation

enum WorkspaceDateLabel {
    static func title(for date: Date, relativeTo today: Date,
                      calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.isDate(date, equalTo: today, toGranularity: .year) ? "EEE MMM d" : "MMM d y"
        )
        return formatter.string(from: date)
    }
}
