import Foundation

/// A named group of students ("Třída").
struct SchoolClass: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Short form used in export file names, e.g. "UDM".
    var abbreviation: String
    var createdAt: Date
    /// Set when the class is archived; archived classes are read-only.
    var archivedAt: Date?
    var students: [Student]
    var lessons: [Lesson]

    init(
        id: UUID = UUID(),
        name: String,
        abbreviation: String? = nil,
        createdAt: Date = .now,
        archivedAt: Date? = nil,
        students: [Student] = [],
        lessons: [Lesson] = []
    ) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation ?? Abbreviation.make(from: name)
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.students = students
        self.lessons = lessons
    }

    var isArchived: Bool { archivedAt != nil }
    var lastLesson: Lesson? { lessons.last }

    /// Drawing, renaming and corrections are possible only in an open lesson: the last one, not closed by hand.
    func isOpen(_ lessonID: UUID) -> Bool {
        guard let lastLesson else { return false }
        return lastLesson.id == lessonID && lastLesson.closedAt == nil
    }

    /// Only the last lesson can be deleted or reopened.
    func isLast(_ lessonID: UUID) -> Bool {
        lastLesson?.id == lessonID
    }

    func student(_ id: UUID) -> Student? {
        students.first { $0.id == id }
    }
    var activeStudents: [Student] { students.filter(\.isActive) }
    var removedStudents: [Student] { students.filter { !$0.isActive } }

    /// Number of recorded draws (present + absent) of a student across all lessons.
    func recordedDrawCount(of studentID: UUID) -> Int {
        lessons.reduce(0) { total, lesson in
            total + lesson.draws.filter { $0.studentID == studentID && $0.result.isRecorded }.count
        }
    }
}

/// A student. The ID is permanent; the name is only display text.
struct Student: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var addedAt: Date
    /// Set when the student is removed from the class; `nil` means active.
    var removedAt: Date?
    /// Draw count assumed for weighting only (never exported). See spec 4, "Nový student".
    var virtualDrawCount: Int

    init(id: UUID = UUID(), name: String, addedAt: Date = .now, removedAt: Date? = nil, virtualDrawCount: Int = 0) {
        self.id = id
        self.name = name
        self.addedAt = addedAt
        self.removedAt = removedAt
        self.virtualDrawCount = virtualDrawCount
    }

    var isActive: Bool { removedAt == nil }
}

/// One meeting of a class ("Hodina").
/// Only the last lesson of a class can be open; all earlier ones are closed for good.
/// The last lesson can also be closed by hand and reopened later.
/// Its Excel export exists only while it is closed (see `SyncFlow`).
struct Lesson: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    /// Set when the last lesson was closed by hand.
    var closedAt: Date?
    /// Path of the Excel export, set while the file exists.
    var exportPath: String?
    var draws: [Draw]

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, exportPath: String? = nil, draws: [Draw] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.exportPath = exportPath
        self.draws = draws
    }

    func result(of studentID: UUID) -> DrawResult? {
        draws.first { $0.studentID == studentID }?.result
    }
}

/// One drawn name within a lesson.
struct Draw: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var studentID: UUID
    var result: DrawResult
    var drawnAt: Date

    init(id: UUID = UUID(), studentID: UUID, result: DrawResult = .pending, drawnAt: Date = .now) {
        self.id = id
        self.studentID = studentID
        self.result = result
        self.drawnAt = drawnAt
    }
}

enum DrawResult: String, Codable, Hashable, Sendable {
    /// Drawn, waiting for an arrow key.
    case pending
    case present
    case absent
    /// Dismissed with left/right arrow: not recorded, but out of the pool for this lesson.
    case skipped

    /// Recorded draws lower the student's weight.
    var isRecorded: Bool { self == .present || self == .absent }
}
