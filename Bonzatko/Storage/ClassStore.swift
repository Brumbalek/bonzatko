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

    /// Deletes the last lesson; the one before becomes the last and can be continued again.
    func deleteLastLesson(in classID: UUID) {
        update(classID) { schoolClass in
            _ = schoolClass.lessons.popLast()
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
        change(&classes[index])
        persist(classes[index])
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
