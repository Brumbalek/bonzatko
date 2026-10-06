import Foundation

/// One status that differs between the app and the edited Excel file.
struct SyncChange: Identifiable, Hashable, Sendable {
    var id: UUID { studentID }
    let studentID: UUID
    let name: String
    let oldStatus: ExcelStatus
    let newStatus: ExcelStatus
}

struct SyncResult: Equatable, Sendable {
    var changes: [SyncChange]
    /// Rows that could not be used (unknown student, unknown status text).
    var warnings: [String]
}

enum ExcelSyncError: LocalizedError, Equatable {
    case missingLessonSheet
    case missingColumns

    var errorDescription: String? {
        switch self {
        case .missingLessonSheet: "V souboru chybí list „Hodina“."
        case .missingColumns: "Na listu „Hodina“ chybí sloupce „Jméno“ a „Stav“."
        }
    }
}

/// Reads the "Hodina" sheet of an export back and compares it with the app's data.
enum ExcelSync {
    struct Row: Equatable, Sendable {
        let name: String
        let statusText: String
        let id: UUID?
    }

    static func readRows(from url: URL) throws -> [Row] {
        let tables = try ImportParser.xlsxTables(url: url)
        guard let table = tables.first(where: { $0.sheetName == LessonExportData.lessonSheetName }) ?? tables.first,
              !table.rows.isEmpty else {
            throw ExcelSyncError.missingLessonSheet
        }
        let headers = table.rows[0].map { Names.clean($0).lowercased(with: Names.czech) }
        guard let nameColumn = headers.firstIndex(of: "jméno"), let statusColumn = headers.firstIndex(of: "stav") else {
            throw ExcelSyncError.missingColumns
        }
        let idColumn = headers.firstIndex(of: "id")
        return table.rows.indices.dropFirst().map { index in
            Row(
                name: Names.clean(table.cell(index, nameColumn)),
                statusText: table.cell(index, statusColumn),
                id: idColumn.flatMap { UUID(uuidString: Names.clean(table.cell(index, $0))) }
            )
        }
    }

    /// Pairs rows with students by the hidden ID, falling back to the name, and lists the differences.
    static func compare(rows: [Row], schoolClass: SchoolClass, lessonID: UUID) -> SyncResult {
        guard let lesson = schoolClass.lessons.first(where: { $0.id == lessonID }) else {
            return SyncResult(changes: [], warnings: [])
        }
        let byID = Dictionary(uniqueKeysWithValues: schoolClass.students.map { ($0.id, $0) })
        let byName = Dictionary(grouping: schoolClass.students, by: { Names.key($0.name) })

        var result = SyncResult(changes: [], warnings: [])
        var seen = Set<UUID>()
        for row in rows {
            let student: Student?
            if let id = row.id, let match = byID[id] {
                student = match
            } else if let matches = byName[Names.key(row.name)], matches.count == 1 {
                student = matches[0]
            } else {
                student = nil
            }
            guard let student else {
                if !row.name.isEmpty {
                    result.warnings.append("Student „\(row.name)“ nebyl ve třídě nalezen – řádek se přeskočí.")
                }
                continue
            }
            guard seen.insert(student.id).inserted else {
                result.warnings.append("Student „\(student.name)“ je v souboru vícekrát – použije se první řádek.")
                continue
            }
            guard let newStatus = ExcelStatus(cellText: row.statusText) else {
                result.warnings.append("U studenta „\(student.name)“ je neznámý stav „\(Names.clean(row.statusText))“ – přeskočí se.")
                continue
            }
            let oldStatus = ExcelStatus(lesson.result(of: student.id))
            if newStatus != oldStatus {
                result.changes.append(SyncChange(studentID: student.id, name: student.name, oldStatus: oldStatus, newStatus: newStatus))
            }
        }
        return result
    }
}
