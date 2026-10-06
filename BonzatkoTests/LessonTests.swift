import Foundation
import Testing
@testable import Bonzatko

struct LessonNamingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }()

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 9))!
    }

    @Test func defaultNameUsesFullClassNameAndDate() {
        let name = LessonNaming.defaultName(className: "Úvod do marketingu", date: date(4), existingNames: [], calendar: calendar)
        #expect(name == "Úvod do marketingu_Hodina261004")
    }

    @Test func secondAndThirdLessonOnTheSameDayGetNumbers() {
        let first = "Úvod do marketingu_Hodina261004"
        let second = LessonNaming.defaultName(className: "Úvod do marketingu", date: date(4), existingNames: [first], calendar: calendar)
        #expect(second == "Úvod do marketingu_Hodina261004_2")
        let third = LessonNaming.defaultName(className: "Úvod do marketingu", date: date(4), existingNames: [first, second], calendar: calendar)
        #expect(third == "Úvod do marketingu_Hodina261004_3")
        let nextDay = LessonNaming.defaultName(className: "Úvod do marketingu", date: date(5), existingNames: [first, second], calendar: calendar)
        #expect(nextDay == "Úvod do marketingu_Hodina261005")
    }

    @Test func renamedLessonFreesItsDefaultName() {
        let name = LessonNaming.defaultName(className: "Účetnictví", date: date(4), existingNames: ["Opakování"], calendar: calendar)
        #expect(name == "Účetnictví_Hodina261004")
    }

    @Test func rejectsEmptyAndDuplicateNames() {
        let first = Lesson(name: "Účetnictví_Hodina261004")
        let second = Lesson(name: "Účetnictví_Hodina261005")
        let schoolClass = SchoolClass(name: "Účetnictví", lessons: [first, second])
        #expect(LessonNaming.validationError(for: "  ", renaming: second.id, in: schoolClass) != nil)
        #expect(LessonNaming.validationError(for: "účetnictví_hodina261004", renaming: second.id, in: schoolClass) != nil)
        #expect(LessonNaming.validationError(for: "Účetnictví_Hodina261005", renaming: second.id, in: schoolClass) == nil)
        #expect(LessonNaming.validationError(for: "Opakování", renaming: second.id, in: schoolClass) == nil)
    }
}

@MainActor
struct LessonStoreTests {
    private func makeStore() -> (ClassStore, URL, UUID) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BonzatkoTests-\(UUID())")
        let store = ClassStore(repository: ClassRepository(directory: directory) { try FileManager.default.removeItem(at: $0) })
        let classID = store.createClass(name: "Úvod do marketingu", abbreviation: "UDM")
        store.addStudents(["Jan Novák", "Eva Dvořáková"], to: classID)
        return (store, directory, classID)
    }

    @Test func newLessonClosesThePreviousOne() throws {
        let (store, _, classID) = makeStore()
        let first = try #require(store.createLesson(in: classID))
        #expect(store.schoolClass(classID)?.isOpen(first) == true)

        let second = try #require(store.createLesson(in: classID))
        let schoolClass = try #require(store.schoolClass(classID))
        #expect(!schoolClass.isOpen(first))
        #expect(schoolClass.isOpen(second))
        #expect(schoolClass.lessons.map(\.name).last?.hasSuffix("_2") == true)
    }

    @Test func onlyTheLastLessonCanBeRenamed() throws {
        let (store, _, classID) = makeStore()
        let first = try #require(store.createLesson(in: classID))
        let second = try #require(store.createLesson(in: classID))

        #expect(store.renameLesson(first, to: "Stará", in: classID) != nil)
        #expect(store.renameLesson(second, to: "  Opakování  před testem ", in: classID) == nil)
        #expect(store.schoolClass(classID)?.lastLesson?.name == "Opakování před testem")
    }

    @Test func deletingTheLastLessonMakesThePreviousOneLastAndReopenable() throws {
        let (store, directory, classID) = makeStore()
        let first = try #require(store.createLesson(in: classID))
        _ = try #require(store.createLesson(in: classID))
        store.deleteLastLesson(in: classID)

        let reloaded = ClassStore(repository: ClassRepository(directory: directory))
        let schoolClass = try #require(reloaded.schoolClass(classID))
        #expect(schoolClass.lessons.map(\.id) == [first])
        #expect(schoolClass.isLast(first))
        #expect(!schoolClass.isOpen(first)) // closed; reopening goes through SyncFlow (reads Excel first)
        reloaded.reopenLastLesson(in: classID)
        #expect(reloaded.schoolClass(classID)?.isOpen(first) == true)
    }

    @Test func archivedClassCannotStartLessons() {
        let (store, _, classID) = makeStore()
        store.archiveClass(classID)
        #expect(store.createLesson(in: classID) == nil)
        #expect(store.schoolClass(classID)?.lessons.isEmpty == true)
    }
}

@MainActor
struct LessonClosingTests {
    private func makeStore() -> (ClassStore, UUID) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BonzatkoTests-\(UUID())")
        let store = ClassStore(repository: ClassRepository(directory: directory) { try FileManager.default.removeItem(at: $0) })
        let classID = store.createClass(name: "Účetnictví", abbreviation: "UCT")
        store.addStudents(["Adam", "Bára"], to: classID)
        return (store, classID)
    }

    @Test func closedLastLessonBlocksDrawingUntilReopened() throws {
        let (store, classID) = makeStore()
        let lessonID = try #require(store.createLesson(in: classID))
        store.closeLastLesson(in: classID)
        #expect(store.schoolClass(classID)?.isOpen(lessonID) == false)
        #expect(store.drawNext(in: classID) == .notAllowed)
        #expect(store.renameLesson(lessonID, to: "Jiná", in: classID) != nil)

        store.reopenLastLesson(in: classID)
        #expect(store.schoolClass(classID)?.isOpen(lessonID) == true)
        if case .drawn = store.drawNext(in: classID) {} else { Issue.record("Expected a draw") }
    }

    @Test func undoAndCorrectionsAreIgnoredInClosedLesson() throws {
        let (store, classID) = makeStore()
        store.createLesson(in: classID)
        _ = store.drawNext(in: classID)
        store.recordResult(.present, in: classID)
        store.closeLastLesson(in: classID)

        store.undoLastStep(in: classID)
        let draw = try #require(store.schoolClass(classID)?.lastLesson?.draws.first)
        store.correctResult(of: draw.id, to: .absent, in: classID)
        #expect(store.schoolClass(classID)?.lastLesson?.draws.map(\.result) == [.present])
    }

    @Test func olderLessonCannotBeReopenedAfterNewOne() throws {
        let (store, classID) = makeStore()
        let first = try #require(store.createLesson(in: classID))
        store.closeLastLesson(in: classID)
        let second = try #require(store.createLesson(in: classID))
        store.reopenLastLesson(in: classID)
        let schoolClass = try #require(store.schoolClass(classID))
        #expect(!schoolClass.isOpen(first))
        #expect(schoolClass.isOpen(second))
    }
}
