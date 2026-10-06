import Foundation
import Observation

/// The app's single source of truth. Every change is written to disk immediately.
@MainActor
@Observable
final class ClassStore {
    private(set) var classes: [SchoolClass] = []
    /// Shown to the user when loading or saving fails.
    var errorMessage: String?

    private let repository: ClassRepository

    init(repository: ClassRepository = ClassRepository()) {
        self.repository = repository
        do {
            let result = try repository.loadAll()
            classes = Names.sortedCzech(result.classes, by: \.name)
            if !result.unreadableFiles.isEmpty {
                let names = result.unreadableFiles.map(\.lastPathComponent).joined(separator: ", ")
                errorMessage = "Některé třídy se nepodařilo načíst (\(names)). Soubory zůstaly beze změny ve složce \(repository.directory.path)."
            }
        } catch {
            errorMessage = "Data se nepodařilo načíst: \(error.localizedDescription)"
        }
    }

    func schoolClass(_ id: UUID) -> SchoolClass? {
        classes.first { $0.id == id }
    }

    // MARK: Classes

    @discardableResult
    func createClass(name: String, abbreviation: String) -> UUID {
        let schoolClass = SchoolClass(name: Names.clean(name), abbreviation: Abbreviation.sanitize(abbreviation))
        classes.append(schoolClass)
        classes = Names.sortedCzech(classes, by: \.name)
        persist(schoolClass)
        return schoolClass.id
    }

    func updateClass(_ id: UUID, name: String, abbreviation: String) {
        update(id) {
            $0.name = Names.clean(name)
            $0.abbreviation = Abbreviation.sanitize(abbreviation)
        }
        classes = Names.sortedCzech(classes, by: \.name)
    }

    func archiveClass(_ id: UUID) {
        update(id, allowArchived: true) { $0.archivedAt = .now }
    }

    func unarchiveClass(_ id: UUID) {
        update(id, allowArchived: true) { $0.archivedAt = nil }
    }

    func deleteClass(_ id: UUID) {
        guard let schoolClass = schoolClass(id) else { return }
        do {
            try repository.moveToTrash(classID: id)
            classes.removeAll { $0.id == id }
        } catch {
            errorMessage = "Třídu „\(schoolClass.name)“ se nepodařilo smazat: \(error.localizedDescription)"
        }
    }

    // MARK: Lessons

    /// Starts a new lesson. The previous lesson is closed for good (it is no longer the last one).
    @discardableResult
    func createLesson(in classID: UUID, date: Date = .now) -> UUID? {
        guard let schoolClass = schoolClass(classID), !schoolClass.isArchived else { return nil }
        let name = LessonNaming.defaultName(className: schoolClass.name, date: date, existingNames: schoolClass.lessons.map(\.name))
        let lesson = Lesson(name: name, createdAt: date)
        update(classID) { $0.lessons.append(lesson) }
        return lesson.id
    }

    /// Renames the open (last) lesson. Returns an error message when the name cannot be used.
    @discardableResult
    func renameLesson(_ lessonID: UUID, to newName: String, in classID: UUID) -> String? {
        guard let schoolClass = schoolClass(classID), schoolClass.isOpen(lessonID), !schoolClass.isArchived else {
            return "Přejmenovat lze jen poslední Hodinu."
        }
        if let error = LessonNaming.validationError(for: newName, renaming: lessonID, in: schoolClass) {
            return error
        }
        update(classID) { schoolClass in
            schoolClass.lessons[schoolClass.lessons.count - 1].name = Names.clean(newName)
        }
        return nil
    }

    /// Closes the last lesson by hand. It can be reopened as long as no newer lesson exists.
    func closeLastLesson(in classID: UUID) {
        update(classID) { schoolClass in
            guard !schoolClass.lessons.isEmpty else { return }
            schoolClass.lessons[schoolClass.lessons.count - 1].closedAt = .now
        }
    }

    func reopenLastLesson(in classID: UUID) {
        update(classID) { schoolClass in
            guard !schoolClass.lessons.isEmpty else { return }
            schoolClass.lessons[schoolClass.lessons.count - 1].closedAt = nil
        }
    }

    /// Deletes the last lesson; the one before becomes the last one, closed, and can be reopened again.
    func deleteLastLesson(in classID: UUID) {
        update(classID) { schoolClass in
            _ = schoolClass.lessons.popLast()
            if !schoolClass.lessons.isEmpty, schoolClass.lessons[schoolClass.lessons.count - 1].closedAt == nil {
                schoolClass.lessons[schoolClass.lessons.count - 1].closedAt = .now
            }
        }
    }

    // MARK: Drawing

    enum DrawOutcome: Equatable {
        case drawn(Student)
        /// The previous name still waits for an arrow key.
        case needsResult
        /// Everybody active has been drawn in this lesson.
        case poolEmpty
        /// The lesson is closed or the class archived.
        case notAllowed
    }

    /// Draws the next student into the open lesson and saves it right away (as pending).
    func drawNext(in classID: UUID) -> DrawOutcome {
        var generator = SystemRandomNumberGenerator()
        return drawNext(in: classID, using: &generator)
    }

    func drawNext<R: RandomNumberGenerator>(in classID: UUID, using generator: inout R) -> DrawOutcome {
        guard let schoolClass = schoolClass(classID), !schoolClass.isArchived, let lesson = schoolClass.lastLesson,
              schoolClass.isOpen(lesson.id) else {
            return .notAllowed
        }
        if lesson.draws.last?.result == .pending {
            return .needsResult
        }
        guard let student = DrawEngine.pick(from: DrawEngine.weightedPool(for: schoolClass, lesson: lesson), using: &generator) else {
            return .poolEmpty
        }
        update(classID) { $0.lessons[$0.lessons.count - 1].draws.append(Draw(studentID: student.id)) }
        return .drawn(student)
    }

    /// Records the arrow-key decision for the pending name.
    func recordResult(_ result: DrawResult, in classID: UUID) {
        updateOpenLesson(classID) { schoolClass in
            let lessonIndex = schoolClass.lessons.count - 1
            guard lessonIndex >= 0, schoolClass.lessons[lessonIndex].draws.last?.result == .pending else { return }
            let drawIndex = schoolClass.lessons[lessonIndex].draws.count - 1
            schoolClass.lessons[lessonIndex].draws[drawIndex].result = result
        }
    }

    /// Undoes the last step: a decided name becomes pending again; a pending name goes back to the pool.
    func undoLastStep(in classID: UUID) {
        updateOpenLesson(classID) { schoolClass in
            let lessonIndex = schoolClass.lessons.count - 1
            guard lessonIndex >= 0, let last = schoolClass.lessons[lessonIndex].draws.last else { return }
            let drawIndex = schoolClass.lessons[lessonIndex].draws.count - 1
            if last.result == .pending {
                schoolClass.lessons[lessonIndex].draws.removeLast()
            } else {
                schoolClass.lessons[lessonIndex].draws[drawIndex].result = .pending
            }
        }
    }

    /// Changes any result of the open lesson from the "Opravit výsledky" panel.
    func correctResult(of drawID: UUID, to result: DrawResult, in classID: UUID) {
        updateOpenLesson(classID) { schoolClass in
            let lessonIndex = schoolClass.lessons.count - 1
            guard lessonIndex >= 0,
                  let drawIndex = schoolClass.lessons[lessonIndex].draws.firstIndex(where: { $0.id == drawID }) else { return }
            schoolClass.lessons[lessonIndex].draws[drawIndex].result = result
        }
    }

    // MARK: Export bookkeeping

    /// Remembers where the lesson's export file is (`nil` once it was removed).
    func setExportPath(_ path: String?, of ref: LessonRef) {
        update(ref.classID, allowArchived: true) { schoolClass in
            guard let index = schoolClass.lessons.firstIndex(where: { $0.id == ref.lessonID }) else { return }
            schoolClass.lessons[index].exportPath = path
        }
    }

    /// Takes over statuses edited in Excel into the last lesson (even if it was closed by hand).
    func applySyncChanges(_ changes: [SyncChange], to ref: LessonRef) {
        update(ref.classID, allowArchived: true) { schoolClass in
            guard let lessonIndex = schoolClass.lessons.firstIndex(where: { $0.id == ref.lessonID }) else { return }
            for change in changes {
                if let drawIndex = schoolClass.lessons[lessonIndex].draws.firstIndex(where: { $0.studentID == change.studentID }) {
                    schoolClass.lessons[lessonIndex].draws[drawIndex].result = change.newStatus.drawResult
                } else if change.newStatus != .empty {
                    schoolClass.lessons[lessonIndex].draws.append(Draw(studentID: change.studentID, result: change.newStatus.drawResult))
                }
            }
        }
    }

    // MARK: Students

    /// Adds names exactly as given (already resolved for duplicates).
    func addStudents(_ names: [String], to classID: UUID) {
        update(classID) { schoolClass in
            let virtualCount = schoolClass.virtualDrawCountForNewStudent()
            for name in names.map(Names.clean) where !name.isEmpty {
                schoolClass.students.append(Student(name: name, virtualDrawCount: virtualCount))
            }
        }
    }

    func renameStudent(_ studentID: UUID, to newName: String, in classID: UUID) {
        let name = Names.clean(newName)
        guard !name.isEmpty else { return }
        update(classID) { schoolClass in
            guard let index = schoolClass.students.firstIndex(where: { $0.id == studentID }) else { return }
            schoolClass.students[index].name = name
        }
    }

    func removeStudents(_ studentIDs: Set<UUID>, from classID: UUID) {
        update(classID) { schoolClass in
            for index in schoolClass.students.indices where studentIDs.contains(schoolClass.students[index].id) {
                schoolClass.students[index].removedAt = .now
            }
        }
    }

    func restoreStudent(_ studentID: UUID, in classID: UUID) {
        update(classID) { schoolClass in
            guard let index = schoolClass.students.firstIndex(where: { $0.id == studentID }) else { return }
            schoolClass.students[index].removedAt = nil
        }
    }

    // MARK: Persistence

    /// Applies a change and saves it. Archived classes are read-only unless `allowArchived` is set.
    private func update(_ classID: UUID, allowArchived: Bool = false, _ change: (inout SchoolClass) -> Void) {
        guard let index = classes.firstIndex(where: { $0.id == classID }),
              allowArchived || !classes[index].isArchived else { return }
        let before = classes[index]
        change(&classes[index])
        guard classes[index] != before else { return }
        persist(classes[index])
    }

    /// Like `update`, but only while the last lesson is open.
    private func updateOpenLesson(_ classID: UUID, _ change: (inout SchoolClass) -> Void) {
        guard let lesson = schoolClass(classID)?.lastLesson, schoolClass(classID)?.isOpen(lesson.id) == true else { return }
        update(classID, change)
    }

    private func persist(_ schoolClass: SchoolClass) {
        do {
            try repository.save(schoolClass)
        } catch {
            errorMessage = "Změny ve třídě „\(schoolClass.name)“ se nepodařilo uložit: \(error.localizedDescription)"
        }
    }
}

extension SchoolClass {
    /// Draw count used for weighting: recorded draws plus the virtual count given on joining.
    func effectiveDrawCount(of student: Student) -> Int {
        recordedDrawCount(of: student.id) + student.virtualDrawCount
    }

    /// A student joining a class with history starts level with the least-drawn active student.
    func virtualDrawCountForNewStudent() -> Int {
        activeStudents.map(effectiveDrawCount(of:)).min() ?? 0
    }
}
