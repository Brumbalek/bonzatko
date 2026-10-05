import Foundation

enum LessonNaming {
    /// "261004" for 4 October 2026.
    static func dateStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d%02d%02d", (parts.year ?? 0) % 100, parts.month ?? 0, parts.day ?? 0)
    }
}
