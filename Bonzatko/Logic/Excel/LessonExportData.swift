import Foundation

/// Status text in the "Stav" column.
enum ExcelStatus: String, CaseIterable, Hashable, Sendable {
    case present = "přítomen"
    case absent = "nepřítomen"
    case empty = ""

    init(_ result: DrawResult?) {
        switch result {
        case .present: self = .present
        case .absent: self = .absent
        case .pending, .skipped, nil: self = .empty
        }
    }

    /// Accepts the exact words regardless of case and surrounding spaces; `nil` for anything else.
    init?(cellText: String) {
        let text = Names.clean(cellText).lowercased(with: Names.czech)
        guard let status = ExcelStatus(rawValue: text) else { return nil }
        self = status
    }

    /// An emptied status means "not recorded".
    var drawResult: DrawResult {
        switch self {
        case .present: .present
        case .absent: .absent
        case .empty: .skipped
        }
    }

    var label: String { self == .empty ? "prázdné" : rawValue }
}

/// Everything that goes into one lesson's workbook, computed from the app's data.
struct LessonExportData: Equatable, Sendable {
    struct LessonRow: Equatable, Sendable {
        let studentID: UUID
        let name: String
        let status: ExcelStatus
    }

    struct SummaryRow: Equatable, Sendable {
        let name: String
        let present: Int
        let absent: Int
        var total: Int { present + absent }
        let note: String
    }

    static let lessonSheetName = "Hodina"
    static let summarySheetName = "Souhrn"
    static let lessonHeaders = ["Jméno", "Stav", "ID"]
    static let summaryHeaders = ["Jméno", "Přítomnosti", "Nepřítomnosti", "Celkem zaznamenán", "Poznámka"]

    let lessonRows: [LessonRow]
    let summaryRows: [SummaryRow]

    init(lessonRows: [LessonRow], summaryRows: [SummaryRow]) {
        self.lessonRows = lessonRows
        self.summaryRows = summaryRows
    }

    /// Sheet 1: all active students with their status in this lesson.
    /// Sheet 2: totals over all lessons up to and including this one; removed students only if they have history.
    init?(schoolClass: SchoolClass, lessonID: UUID) {
        guard let lessonIndex = schoolClass.lessons.firstIndex(where: { $0.id == lessonID }) else { return nil }
        let lesson = schoolClass.lessons[lessonIndex]
        let lessonsSoFar = schoolClass.lessons[...lessonIndex]

        lessonRows = Names.sortedCzech(schoolClass.activeStudents, by: \.name).map {
            LessonRow(studentID: $0.id, name: $0.name, status: ExcelStatus(lesson.result(of: $0.id)))
        }

        let drawsSoFar = lessonsSoFar.flatMap(\.draws)
        summaryRows = Names.sortedCzech(schoolClass.students, by: \.name).compactMap { student in
            let draws = drawsSoFar.filter { $0.studentID == student.id }
            guard student.isActive || !draws.isEmpty else { return nil }
            let present = draws.filter { $0.result == .present }.count
            let absent = draws.filter { $0.result == .absent }.count
            let note: String
            if !student.isActive {
                note = "odebrán"
            } else if present + absent == 0 {
                note = "Zatím nevylosován"
            } else {
                note = ""
            }
            return SummaryRow(name: student.name, present: present, absent: absent, note: note)
        }
    }
}

enum ExportPaths {
    /// "~/Desktop/Bonzátko"
    static var defaultRoot: URL {
        URL.desktopDirectory.appending(path: "Bonzátko", directoryHint: .isDirectory)
    }

    static func classFolder(root: URL, className: String) -> URL {
        let name = FileNameSanitizer.sanitize(className)
        return root.appending(path: name.isEmpty ? Abbreviation.fallback : name, directoryHint: .isDirectory)
    }

    /// Lesson name with the full class name replaced by the abbreviation: "UDM_Hodina261004.xlsx".
    static func fileName(lessonName: String, className: String, abbreviation: String) -> String {
        var name = lessonName
        if !className.isEmpty, let range = name.range(of: className) {
            name.replaceSubrange(range, with: abbreviation)
        }
        let sanitized = FileNameSanitizer.sanitize(name)
        return (sanitized.isEmpty ? "Hodina" : sanitized) + ".xlsx"
    }

    static func fileURL(root: URL, schoolClass: SchoolClass, lesson: Lesson) -> URL {
        classFolder(root: root, className: schoolClass.name)
            .appending(path: fileName(lessonName: lesson.name, className: schoolClass.name, abbreviation: schoolClass.abbreviation))
    }

    /// Excel marks an open workbook with a "~$…" file next to it (long names may be shortened from the start).
    static func isLockedByExcel(_ file: URL) -> Bool {
        let folder = file.deletingLastPathComponent()
        let name = file.lastPathComponent
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return items.contains { item in
            guard item.hasPrefix("~$") else { return false }
            let rest = item.dropFirst(2)
            return !rest.isEmpty && name.hasSuffix(rest)
        }
    }
}
