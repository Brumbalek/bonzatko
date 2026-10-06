import Foundation
import Observation

/// Lesson life cycle around the Excel file. Only one side can change a lesson at a time:
/// - open lesson: only the app; no file exists,
/// - closed (last) lesson: only Excel; the file exists and may be edited,
/// - reopening reads the edits back (after confirmation) and moves the file to the Trash,
/// - a new lesson closes the previous one for good and makes its file read-only.
@MainActor
@Observable
final class SyncFlow {
    enum Step: Identifiable, Equatable {
        case confirmNewLesson(previousName: String)
        case excelOpen(fileName: String)
        case cannotRead(message: String)
        case review(SyncResult, fileName: String)

        var id: String {
            switch self {
            case .confirmNewLesson: "confirm"
            case .excelOpen: "open"
            case .cannotRead: "read"
            case .review: "review"
            }
        }
    }

    enum Purpose: Equatable {
        case reopen(thenShow: Bool)
        case newLesson
    }

    /// The step currently waiting for the user; `nil` when nothing is shown.
    var step: Step?
    private(set) var purpose: Purpose?

    private let store: ClassStore
    private let exporter: ExportCenter
    private let navigator: Navigator
    private var ref: LessonRef?

    init(store: ClassStore, exporter: ExportCenter, navigator: Navigator) {
        self.store = store
        self.exporter = exporter
        self.navigator = navigator
    }

    // MARK: Entry points

    /// "Uzavřít Hodinu": the lesson is closed and its file written.
    func close(_ lesson: LessonRef) {
        store.closeLastLesson(in: lesson.classID)
        if navigator.openLesson == lesson { navigator.openLesson = nil }
        switch exporter.write(lesson) {
        case .exported(let url):
            exporter.notice = .init(message: "Hodina je uzavřená a uložená do Excelu: \(url.lastPathComponent)", fileURL: url, isError: false)
        case .locked:
            break // the exporter tells the user and retries on its own
        case .failed(let message):
            exporter.notice = .init(message: "Export se nepodařil: \(message) Data jsou v bezpečí v aplikaci.", fileURL: nil, isError: true)
        }
    }

    /// "Pokračovat" / "Znovu otevřít": reads edits from Excel first, then removes the file and opens the lesson.
    func reopen(_ lesson: LessonRef, thenShow: Bool) {
        guard let schoolClass = store.schoolClass(lesson.classID), schoolClass.isLast(lesson.lessonID) else { return }
        if schoolClass.isOpen(lesson.lessonID) {
            if thenShow { navigator.openLesson = lesson }
            return
        }
        start(.reopen(thenShow: thenShow), lesson)
        readExcel()
    }

    func requestNewLesson(in classID: UUID) {
        guard let schoolClass = store.schoolClass(classID) else { return }
        guard let previous = schoolClass.lastLesson else {
            createAndOpenLesson(in: classID)
            return
        }
        start(.newLesson, LessonRef(classID: classID, lessonID: previous.id))
        step = .confirmNewLesson(previousName: previous.name)
    }

    func confirmNewLesson() {
        step = nil
        guard let ref, let schoolClass = store.schoolClass(ref.classID) else { return reset() }
        if schoolClass.isOpen(ref.lessonID) {
            // Still open in the app: nothing can have been edited in Excel.
            store.closeLastLesson(in: ref.classID)
            finish(applying: [])
        } else {
            readExcel()
        }
    }

    /// Deletes the last lesson; the previous one becomes the last, closed one, and its file editable again.
    func deleteLastLesson(in classID: UUID) {
        if let open = navigator.openLesson, open.classID == classID { navigator.openLesson = nil }
        store.deleteLastLesson(in: classID)
        if let previous = store.schoolClass(classID)?.lastLesson {
            exporter.unfinalize(LessonRef(classID: classID, lessonID: previous.id))
        }
    }

    // MARK: Answers from the dialogs

    func retryReading() {
        step = nil
        readExcel()
    }

    /// Continue with the app's data only (file missing, unreadable, or Excel left a stale lock).
    func continueWithoutExcel() {
        step = nil
        finish(applying: [])
    }

    func apply(_ changes: [SyncChange]) {
        step = nil
        finish(applying: changes)
    }

    func cancel() {
        step = nil
        reset()
    }

    // MARK: Steps

    private func start(_ purpose: Purpose, _ lesson: LessonRef) {
        self.purpose = purpose
        ref = lesson
    }

    /// Reads the closed lesson's file and shows the edits made in Excel (spec chapter 6).
    private func readExcel() {
        guard let ref, let lesson = store.schoolClass(ref.classID)?.lessons.first(where: { $0.id == ref.lessonID }) else {
            return reset()
        }
        guard let path = lesson.exportPath else {
            finish(applying: []) // never exported, nothing to read
            return
        }
        let url = URL(filePath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            step = .cannotRead(message: "Soubor \(url.lastPathComponent) nebyl nalezen. Pokračuji s daty aplikace.")
            return
        }
        guard !ExportPaths.isLockedByExcel(url) else {
            step = .excelOpen(fileName: url.lastPathComponent)
            return
        }
        do {
            let rows = try ExcelSync.readRows(from: url)
            guard let schoolClass = store.schoolClass(ref.classID) else { return reset() }
            let result = ExcelSync.compare(rows: rows, schoolClass: schoolClass, lessonID: ref.lessonID)
            if result.changes.isEmpty && result.warnings.isEmpty {
                finish(applying: [])
            } else {
                step = .review(result, fileName: url.lastPathComponent)
            }
        } catch {
            step = .cannotRead(message: "Soubor \(url.lastPathComponent) se nepodařilo přečíst: \(error.localizedDescription) Pokračuji s daty aplikace.")
        }
    }

    private func finish(applying changes: [SyncChange]) {
        guard let ref, let purpose else { return reset() }
        if !changes.isEmpty {
            store.applySyncChanges(changes, to: ref)
        }
        switch purpose {
        case .reopen(let thenShow):
            exporter.remove(ref)
            store.reopenLastLesson(in: ref.classID)
            if thenShow { navigator.openLesson = ref }

        case .newLesson:
            // Final version of the previous lesson, then it is locked for good.
            switch exporter.write(ref) {
            case .exported:
                exporter.finalize(ref)
            case .locked:
                break
            case .failed(let message):
                exporter.notice = .init(message: "Export předchozí Hodiny se nepodařil: \(message) Data jsou v bezpečí v aplikaci.",
                                        fileURL: nil, isError: true)
            }
            createAndOpenLesson(in: ref.classID)
        }
        reset()
    }

    private func createAndOpenLesson(in classID: UUID) {
        if let lessonID = store.createLesson(in: classID) {
            navigator.openLesson = LessonRef(classID: classID, lessonID: lessonID)
        }
    }

    private func reset() {
        purpose = nil
        ref = nil
    }
}
