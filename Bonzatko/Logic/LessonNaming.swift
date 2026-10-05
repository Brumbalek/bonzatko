import Foundation

enum LessonNaming {
    /// "261004" for 4 October 2026.
    static func dateStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d%02d%02d", (parts.year ?? 0) % 100, parts.month ?? 0, parts.day ?? 0)
    }

    /// "<class name>_HodinaYYMMDD", or "…_2", "…_3" when that name is already used in the class.
    static func defaultName(className: String, date: Date, existingNames: [String], calendar: Calendar = .current) -> String {
        let base = "\(Names.clean(className))_Hodina\(dateStamp(date, calendar: calendar))"
        let taken = Set(existingNames.map(Names.key))
        guard taken.contains(Names.key(base)) else { return base }
        var number = 2
        while taken.contains(Names.key("\(base)_\(number)")) {
            number += 1
        }
        return "\(base)_\(number)"
    }

    /// Returns a Czech error message when the name cannot be used, otherwise `nil`.
    static func validationError(for name: String, renaming lessonID: UUID, in schoolClass: SchoolClass) -> String? {
        let cleaned = Names.clean(name)
        if cleaned.isEmpty {
            return "Název Hodiny nesmí být prázdný."
        }
        let clash = schoolClass.lessons.contains { $0.id != lessonID && Names.key($0.name) == Names.key(cleaned) }
        if clash {
            return "Hodina „\(cleaned)“ už v této třídě existuje. Zvolte jiný název, aby se exporty nepřepsaly."
        }
        return nil
    }
}
