import Foundation
import Testing
import ZIPFoundation
@testable import Bonzatko

/// Fictional class used by the export tests.
private struct Fixture {
    let adam = Student(name: "Adam Bílý")
    let bara = Student(name: "Bára Černá")
    let chrudos = Student(name: "Chrudoš Hrubý")
    let cyril = Student(name: "Cyril Dub")
    let removedWithHistory = Student(name: "Emil Fiala", removedAt: .now)
    let removedWithoutHistory = Student(name: "Filip Gregor", removedAt: .now)
    let first: Lesson
    let second: Lesson
    let schoolClass: SchoolClass

    init() {
        first = Lesson(name: "Úvod do marketingu_Hodina261001", draws: [
            Draw(studentID: adam.id, result: .present),
            Draw(studentID: removedWithHistory.id, result: .absent),
            Draw(studentID: bara.id, result: .skipped),
        ])
        second = Lesson(name: "Úvod do marketingu_Hodina261004", draws: [
            Draw(studentID: bara.id, result: .absent),
            Draw(studentID: adam.id, result: .present),
            Draw(studentID: cyril.id, result: .pending),
        ])
        schoolClass = SchoolClass(name: "Úvod do marketingu", abbreviation: "UDM",
                                  students: [cyril, bara, adam, chrudos, removedWithHistory, removedWithoutHistory],
                                  lessons: [first, second])
    }
}

struct LessonExportDataTests {
    @Test func lessonSheetListsActiveStudentsAlphabeticallyWithStatus() throws {
        let fixture = Fixture()
        let data = try #require(LessonExportData(schoolClass: fixture.schoolClass, lessonID: fixture.second.id))
        #expect(data.lessonRows.map(\.name) == ["Adam Bílý", "Bára Černá", "Cyril Dub", "Chrudoš Hrubý"])
        #expect(data.lessonRows.map(\.status) == [.present, .absent, .empty, .empty])
        #expect(data.lessonRows.map(\.studentID) == [fixture.adam.id, fixture.bara.id, fixture.cyril.id, fixture.chrudos.id])
    }

    @Test func summaryCountsAllLessonsUpToThisOne() throws {
        let fixture = Fixture()
        let data = try #require(LessonExportData(schoolClass: fixture.schoolClass, lessonID: fixture.second.id))
        #expect(data.summaryRows == [
            .init(name: "Adam Bílý", present: 2, absent: 0, note: ""),
            .init(name: "Bára Černá", present: 0, absent: 1, note: ""),
            .init(name: "Cyril Dub", present: 0, absent: 0, note: "Zatím nevylosován"),
            .init(name: "Emil Fiala", present: 0, absent: 1, note: "odebrán"),
            .init(name: "Chrudoš Hrubý", present: 0, absent: 0, note: "Zatím nevylosován"),
        ])

        let earlier = try #require(LessonExportData(schoolClass: fixture.schoolClass, lessonID: fixture.first.id))
        #expect(earlier.summaryRows.first { $0.name == "Adam Bílý" }?.present == 1)
    }

    @Test func fileNamesUseAbbreviation() {
        #expect(ExportPaths.fileName(lessonName: "Úvod do marketingu_Hodina261004", className: "Úvod do marketingu", abbreviation: "UDM")
            == "UDM_Hodina261004.xlsx")
        #expect(ExportPaths.fileName(lessonName: "Úvod do marketingu_Hodina261004_2", className: "Úvod do marketingu", abbreviation: "UDM")
            == "UDM_Hodina261004_2.xlsx")
        #expect(ExportPaths.fileName(lessonName: "Opakování: test/zkouška", className: "Úvod do marketingu", abbreviation: "UDM")
            == "Opakování_ test_zkouška.xlsx")
        let folder = ExportPaths.classFolder(root: URL(filePath: "/tmp/B"), className: "Účetnictví A/B")
        #expect(folder.lastPathComponent == "Účetnictví A_B")
    }

    @Test func excelLockFileIsDetected() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "BonzatkoTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "UDM_Hodina261004.xlsx")
        #expect(!ExportPaths.isLockedByExcel(file))
        try Data().write(to: folder.appending(path: "~$UDM_Hodina261004.xlsx"))
        #expect(ExportPaths.isLockedByExcel(file))
        #expect(!ExportPaths.isLockedByExcel(folder.appending(path: "UCT_Hodina261004.xlsx")))
    }

    @Test func excelStatusParsing() {
        #expect(ExcelStatus(cellText: " Přítomen ") == .present)
        #expect(ExcelStatus(cellText: "NEPŘÍTOMEN") == .absent)
        #expect(ExcelStatus(cellText: "  ") == .empty)
        #expect(ExcelStatus(cellText: "ano") == nil)
    }
}

struct ExcelRoundTripTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "BonzatkoTests-\(UUID()).xlsx")
    }

    private func entry(_ name: String, in url: URL) throws -> String {
        let archive = try Archive(url: url, accessMode: .read)
        var data = Data()
        _ = try archive.extract(try #require(archive[name])) { data.append($0) }
        return String(decoding: data, as: UTF8.self)
    }

    @Test func exportReadsBackWithoutDifferences() throws {
        let fixture = Fixture()
        let data = try #require(LessonExportData(schoolClass: fixture.schoolClass, lessonID: fixture.second.id))
        let url = temporaryFile()
        try ExcelWriter.write(data, to: url)

        let rows = try ExcelSync.readRows(from: url)
        #expect(rows.map(\.name) == data.lessonRows.map(\.name))
        #expect(rows.map(\.id) == data.lessonRows.map(\.studentID))
        let result = ExcelSync.compare(rows: rows, schoolClass: fixture.schoolClass, lessonID: fixture.second.id)
        #expect(result.changes.isEmpty)
        #expect(result.warnings.isEmpty)

        // Summary sheet is there too.
        let tables = try ImportParser.xlsxTables(url: url)
        #expect(tables.map(\.sheetName) == ["Hodina", "Souhrn"])
        #expect(tables[1].rows[0] == LessonExportData.summaryHeaders)
        #expect(tables[1].rows[1] == ["Adam Bílý", "2", "0", "2"])
    }

    @Test func workbookHasDropDownConditionalFormattingAndHiddenID() throws {
        let fixture = Fixture()
        let url = temporaryFile()
        try ExcelWriter.write(try #require(LessonExportData(schoolClass: fixture.schoolClass, lessonID: fixture.second.id)), to: url)
        let sheet = try entry("xl/worksheets/sheet1.xml", in: url)

        #expect(sheet.contains(#"<dataValidation type="list""#))
        #expect(sheet.contains(#"sqref="B2:B5""#))
        #expect(sheet.contains("&quot;přítomen,nepřítomen&quot;") || sheet.contains("\"přítomen,nepřítomen\""))
        #expect(sheet.contains(#"<conditionalFormatting sqref="A2:C5">"#))
        #expect(sheet.contains("$B2=&quot;přítomen&quot;") || sheet.contains("$B2=\"přítomen\""))
        #expect(sheet.contains("$B2=&quot;nepřítomen&quot;") || sheet.contains("$B2=\"nepřítomen\""))
        #expect(sheet.contains(#"<col min="3" max="3""#) && sheet.contains(#"hidden="1""#))
    }

    @Test func statusesEditedInExcelAreFoundByIDAndByName() throws {
        let fixture = Fixture()
        let rows = [
            ExcelSync.Row(name: "Adam Bílý", statusText: "nepřítomen", id: fixture.adam.id), // changed
            ExcelSync.Row(name: "Bára Černá", statusText: "", id: fixture.bara.id),           // cleared
            ExcelSync.Row(name: "Cyril Dub", statusText: "přítomen", id: nil),                // by name, newly recorded
            ExcelSync.Row(name: "Přejmenovaný", statusText: "", id: fixture.chrudos.id),      // renamed in Excel, same ID
            ExcelSync.Row(name: "Neznámý Student", statusText: "přítomen", id: nil),
            ExcelSync.Row(name: "Emil Fiala", statusText: "ano", id: fixture.removedWithHistory.id),
        ]
        let result = ExcelSync.compare(rows: rows, schoolClass: fixture.schoolClass, lessonID: fixture.second.id)
        #expect(result.changes.map(\.name) == ["Adam Bílý", "Bára Černá", "Cyril Dub"])
        #expect(result.changes.map(\.newStatus) == [.absent, .empty, .present])
        #expect(result.changes.map(\.oldStatus) == [.present, .absent, .empty])
        #expect(result.warnings.count == 2)
    }

    @Test func fullRoundTripWithEditInExcel() throws {
        let fixture = Fixture()
        let url = temporaryFile()
        // The teacher marks Chrudoš present in Excel: simulate by writing a workbook with that status.
        var edited = try #require(LessonExportData(schoolClass: fixture.schoolClass, lessonID: fixture.second.id))
        edited = LessonExportData(lessonRows: edited.lessonRows.map {
            $0.studentID == fixture.chrudos.id ? .init(studentID: $0.studentID, name: $0.name, status: .present) : $0
        }, summaryRows: edited.summaryRows)
        try ExcelWriter.write(edited, to: url)

        let result = ExcelSync.compare(rows: try ExcelSync.readRows(from: url), schoolClass: fixture.schoolClass, lessonID: fixture.second.id)
        #expect(result.changes == [SyncChange(studentID: fixture.chrudos.id, name: "Chrudoš Hrubý", oldStatus: .empty, newStatus: .present)])
    }
}

@MainActor
struct LessonFileLifecycleTests {
    private struct Environment {
        let store: ClassStore
        let exporter: ExportCenter
        let flow: SyncFlow
        let navigator: Navigator
        let classID: UUID
        let root: URL
    }

    private func makeEnvironment() throws -> Environment {
        let base = FileManager.default.temporaryDirectory.appending(path: "BonzatkoTests-\(UUID())")
        let remove: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
        let store = ClassStore(repository: ClassRepository(directory: base.appending(path: "data"), discardFile: remove))
        let defaults = try #require(UserDefaults(suiteName: "BonzatkoTests-\(UUID())"))
        let root = base.appending(path: "Bonzátko")
        defaults.set(root.path, forKey: SettingsKeys.exportRoot)
        let exporter = ExportCenter(store: store, defaults: defaults, discardFile: remove)
        let navigator = Navigator()
        let flow = SyncFlow(store: store, exporter: exporter, navigator: navigator)

        let classID = store.createClass(name: "Úvod do marketingu", abbreviation: "UDM")
        store.addStudents(["Adam Bílý", "Bára Černá", "Cyril Dub"], to: classID)
        flow.requestNewLesson(in: classID)
        return Environment(store: store, exporter: exporter, flow: flow, navigator: navigator, classID: classID, root: root)
    }

    private func lastRef(_ env: Environment) throws -> LessonRef {
        LessonRef(classID: env.classID, lessonID: try #require(env.store.schoolClass(env.classID)?.lastLesson?.id))
    }

    private func drawAndRecord(_ env: Environment, _ result: DrawResult) throws -> UUID {
        guard case .drawn(let student) = env.store.drawNext(in: env.classID) else { throw CancellationError() }
        env.store.recordResult(result, in: env.classID)
        return student.id
    }

    /// Simulates the teacher changing a status in Excel and saving the file.
    private func editInExcel(_ env: Environment, _ ref: LessonRef, studentID: UUID, to status: ExcelStatus) throws {
        let file = try #require(env.exporter.existingFile(of: ref))
        let schoolClass = try #require(env.store.schoolClass(env.classID))
        let data = try #require(LessonExportData(schoolClass: schoolClass, lessonID: ref.lessonID))
        let edited = LessonExportData(lessonRows: data.lessonRows.map {
            $0.studentID == studentID ? .init(studentID: $0.studentID, name: $0.name, status: status) : $0
        }, summaryRows: data.summaryRows)
        try ExcelWriter.write(edited, to: file)
    }

    @Test func openLessonHasNoFileAndClosingWritesIt() throws {
        let env = try makeEnvironment()
        let ref = try lastRef(env)
        #expect(env.navigator.openLesson == ref)
        #expect(env.exporter.existingFile(of: ref) == nil)

        _ = try drawAndRecord(env, .present)
        env.flow.close(ref)
        let file = try #require(env.exporter.existingFile(of: ref))
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(file.lastPathComponent.hasPrefix("UDM_Hodina"))
        #expect(file.deletingLastPathComponent().lastPathComponent == "Úvod do marketingu")
        #expect(env.store.schoolClass(env.classID)?.isOpen(ref.lessonID) == false)
        #expect(env.navigator.openLesson == nil)
        #expect(!ExportCenter.isReadOnly(file))
    }

    @Test func reopeningTakesOverExcelEditsAndRemovesTheFile() throws {
        let env = try makeEnvironment()
        let ref = try lastRef(env)
        let drawn = try drawAndRecord(env, .present)
        env.flow.close(ref)
        let file = try #require(env.exporter.existingFile(of: ref))

        try editInExcel(env, ref, studentID: drawn, to: .absent)
        env.flow.reopen(ref, thenShow: true)
        guard case .review(let result, _) = env.flow.step else {
            Issue.record("Expected the review of Excel edits")
            return
        }
        // Only the edit made in Excel is listed.
        #expect(result.changes.map(\.studentID) == [drawn])
        #expect(result.changes.first?.oldStatus == .present)
        #expect(result.changes.first?.newStatus == .absent)

        env.flow.apply(result.changes)
        #expect(env.store.schoolClass(env.classID)?.lastLesson?.result(of: drawn) == .absent)
        #expect(env.store.schoolClass(env.classID)?.isOpen(ref.lessonID) == true)
        #expect(env.navigator.openLesson == ref)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(env.exporter.existingFile(of: ref) == nil)
    }

    @Test func decliningExcelEditsKeepsAppDataAndNextCloseWritesFreshFile() throws {
        let env = try makeEnvironment()
        let ref = try lastRef(env)
        let drawn = try drawAndRecord(env, .present)
        env.flow.close(ref)
        try editInExcel(env, ref, studentID: drawn, to: .absent)

        env.flow.reopen(ref, thenShow: false)
        env.flow.apply([]) // "Nepřevzít"
        #expect(env.store.schoolClass(env.classID)?.lastLesson?.result(of: drawn) == .present)

        // Continue drawing, close again: the new file holds the app's data only.
        let second = try drawAndRecord(env, .absent)
        env.flow.close(ref)
        let closedFile = try #require(env.exporter.existingFile(of: ref))
        let rows = try ExcelSync.readRows(from: closedFile)
        #expect(rows.first { $0.id == drawn }?.statusText == "přítomen")
        #expect(rows.first { $0.id == second }?.statusText == "nepřítomen")
    }

    @Test func reopeningWithoutEditsOpensDirectly() throws {
        let env = try makeEnvironment()
        let ref = try lastRef(env)
        env.flow.close(ref)
        env.flow.reopen(ref, thenShow: true)
        #expect(env.flow.step == nil)
        #expect(env.navigator.openLesson == ref)
        #expect(env.exporter.existingFile(of: ref) == nil)
    }

    @Test func fileOpenInExcelBlocksReopeningUntilClosed() throws {
        let env = try makeEnvironment()
        let ref = try lastRef(env)
        env.flow.close(ref)
        let file = try #require(env.exporter.existingFile(of: ref))
        let lock = file.deletingLastPathComponent().appending(path: "~$" + file.lastPathComponent)
        try Data().write(to: lock)

        env.flow.reopen(ref, thenShow: true)
        #expect(env.flow.step == .excelOpen(fileName: file.lastPathComponent))
        #expect(env.store.schoolClass(env.classID)?.isOpen(ref.lessonID) == false)

        try FileManager.default.removeItem(at: lock)
        env.flow.retryReading()
        #expect(env.store.schoolClass(env.classID)?.isOpen(ref.lessonID) == true)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func newLessonReadsEditsOfClosedLessonAndLocksItsFile() throws {
        let env = try makeEnvironment()
        let first = try lastRef(env)
        let drawn = try drawAndRecord(env, .absent)
        env.flow.close(first)
        try editInExcel(env, first, studentID: drawn, to: .present)

        env.flow.requestNewLesson(in: env.classID)
        let previousName = try #require(env.store.schoolClass(env.classID)?.lessons.first?.name)
        #expect(env.flow.step == .confirmNewLesson(previousName: previousName))
        env.flow.confirmNewLesson()
        guard case .review(let result, _) = env.flow.step else {
            Issue.record("Expected the review of Excel edits")
            return
        }
        env.flow.apply(result.changes)

        let schoolClass = try #require(env.store.schoolClass(env.classID))
        #expect(schoolClass.lessons.count == 2)
        #expect(schoolClass.lessons[0].result(of: drawn) == .present)
        #expect(env.navigator.openLesson?.lessonID == schoolClass.lessons[1].id)

        // The previous file is final: rewritten with the taken-over data and read-only.
        let file = try #require(env.exporter.existingFile(of: first))
        #expect(ExportCenter.isReadOnly(file))
        #expect(try ExcelSync.readRows(from: file).first { $0.id == drawn }?.statusText == "přítomen")
    }

    @Test func newLessonWhilePreviousIsOpenClosesAndExportsIt() throws {
        let env = try makeEnvironment()
        let first = try lastRef(env)
        _ = try drawAndRecord(env, .present)
        env.flow.requestNewLesson(in: env.classID)
        env.flow.confirmNewLesson()
        #expect(env.flow.step == nil)
        let file = try #require(env.exporter.existingFile(of: first))
        #expect(ExportCenter.isReadOnly(file))
        #expect(env.store.schoolClass(env.classID)?.lessons.count == 2)
    }

    @Test func deletingLastLessonMakesPreviousFileEditableAgain() throws {
        let env = try makeEnvironment()
        let first = try lastRef(env)
        env.flow.requestNewLesson(in: env.classID)
        env.flow.confirmNewLesson()
        let file = try #require(env.exporter.existingFile(of: first))
        #expect(ExportCenter.isReadOnly(file))

        env.flow.deleteLastLesson(in: env.classID)
        let schoolClass = try #require(env.store.schoolClass(env.classID))
        #expect(schoolClass.lastLesson?.id == first.lessonID)
        #expect(!schoolClass.isOpen(first.lessonID)) // closed, reopenable
        #expect(!ExportCenter.isReadOnly(file))

        env.flow.reopen(first, thenShow: false)
        #expect(env.store.schoolClass(env.classID)?.isOpen(first.lessonID) == true)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func fileOpenInExcelIsNotOverwrittenOnClose() throws {
        let env = try makeEnvironment()
        let ref = try lastRef(env)
        env.flow.close(ref)
        let file = try #require(env.exporter.existingFile(of: ref))
        env.flow.reopen(ref, thenShow: false)

        // A stale copy of the same name is open in Excel when the lesson is closed again.
        try Data().write(to: file)
        let lock = file.deletingLastPathComponent().appending(path: "~$" + file.lastPathComponent)
        try Data().write(to: lock)
        #expect(env.exporter.write(ref) == .locked(file))
        #expect(env.exporter.isWaitingForExcel)
        try FileManager.default.removeItem(at: lock)
        #expect(env.exporter.write(ref) == .exported(file))
    }
}
