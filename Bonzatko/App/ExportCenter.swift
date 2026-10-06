import AppKit
import Foundation
import Observation

/// File side of the export: writes, removes and finalizes lesson workbooks.
///
/// Rule: a lesson's file exists only while the lesson is closed. Closing writes it, reopening reads it
/// back and removes it, starting a new lesson makes the previous file final (read-only).
@MainActor
@Observable
final class ExportCenter {
    enum Outcome: Equatable {
        case exported(URL)
        /// Excel has a file of that name open; the export is retried automatically once it is closed.
        case locked(URL)
        case failed(String)
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let fileURL: URL?
        let isError: Bool
    }

    /// Latest message for the user (shown as a banner).
    var notice: Notice?

    private let store: ClassStore
    private let defaults: UserDefaults
    private let discardFile: (URL) throws -> Void
    private var waitingForExcel: [LessonRef: URL] = [:]
    private var retryTask: Task<Void, Never>?

    init(
        store: ClassStore,
        defaults: UserDefaults = .standard,
        discardFile: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.store = store
        self.defaults = defaults
        self.discardFile = discardFile
    }

    var root: URL {
        if let path = defaults.string(forKey: SettingsKeys.exportRoot), !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return ExportPaths.defaultRoot
    }

    var isWaitingForExcel: Bool { !waitingForExcel.isEmpty }

    /// The existing export file of a lesson, if any.
    func existingFile(of ref: LessonRef) -> URL? {
        guard let path = lesson(ref)?.exportPath else { return nil }
        return URL(filePath: path)
    }

    // MARK: Write

    /// Writes (or rewrites) the lesson's workbook. Never touches a file that Excel has open.
    @discardableResult
    func write(_ ref: LessonRef) -> Outcome {
        guard let schoolClass = store.schoolClass(ref.classID),
              let lesson = lesson(ref),
              let data = LessonExportData(schoolClass: schoolClass, lessonID: ref.lessonID) else {
            return .failed("Hodina nebyla nalezena.")
        }
        let target = ExportPaths.fileURL(root: root, schoolClass: schoolClass, lesson: lesson)
        let previous = lesson.exportPath.map { URL(filePath: $0) }

        for file in [previous, target].compactMap({ $0 }) where ExportPaths.isLockedByExcel(file) {
            waitForExcel(ref, file: file)
            return .locked(file)
        }
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Write next to the target first, then swap it in, so a failure never leaves half a file.
            let temporary = target.deletingLastPathComponent().appending(path: ".bonzatko-\(UUID().uuidString).xlsx")
            try ExcelWriter.write(data, to: temporary)
            if fileManager.fileExists(atPath: target.path) {
                try setReadOnly(false, target)
                _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: target)
            }
            // Class renamed since the last export: the old file is replaced by the new one.
            if let previous, previous.standardizedFileURL != target.standardizedFileURL,
               fileManager.fileExists(atPath: previous.path) {
                try? setReadOnly(false, previous)
                try? discardFile(previous)
            }
            store.setExportPath(target.path, of: ref)
            waitingForExcel[ref] = nil
            return .exported(target)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: Remove / finalize

    /// Moves the export to the Trash (when the lesson is reopened).
    func remove(_ ref: LessonRef) {
        waitingForExcel[ref] = nil
        guard let file = existingFile(of: ref) else { return }
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                try setReadOnly(false, file)
                try discardFile(file)
            } catch {
                notice = Notice(message: "Soubor \(file.lastPathComponent) se nepodařilo přesunout do Koše: \(error.localizedDescription)",
                                fileURL: file, isError: true)
            }
        }
        store.setExportPath(nil, of: ref)
    }

    /// Marks the file of a lesson that will never change again as locked (Finder: Informace → Zamčeno).
    func finalize(_ ref: LessonRef) {
        guard let file = existingFile(of: ref), FileManager.default.fileExists(atPath: file.path) else { return }
        try? setReadOnly(true, file)
    }

    /// The file becomes editable again (the lesson became the last one after a deletion).
    func unfinalize(_ ref: LessonRef) {
        guard let file = existingFile(of: ref), FileManager.default.fileExists(atPath: file.path) else { return }
        try? setReadOnly(false, file)
    }

    static func isReadOnly(_ file: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else { return false }
        let locked = (attributes[.immutable] as? Bool) ?? false
        let permissions = (attributes[.posixPermissions] as? Int) ?? 0o644
        return locked && permissions & 0o222 == 0
    }

    /// Read-only permissions make Excel open the file as read-only right away;
    /// the Finder lock ("Zamčeno") additionally stops any app from replacing it.
    private func setReadOnly(_ readOnly: Bool, _ file: URL) throws {
        let fileManager = FileManager.default
        if readOnly {
            try fileManager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
            try fileManager.setAttributes([.immutable: true], ofItemAtPath: file.path)
        } else {
            try fileManager.setAttributes([.immutable: false], ofItemAtPath: file.path)
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        }
    }

    // MARK: Waiting for Excel

    private func waitForExcel(_ ref: LessonRef, file: URL) {
        waitingForExcel[ref] = file
        notice = Notice(message: "Soubor \(file.lastPathComponent) je otevřený v Excelu. Data jsou v bezpečí v aplikaci; export proběhne sám, jakmile soubor zavřete.",
                        fileURL: nil, isError: true)
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            while let self, !self.waitingForExcel.isEmpty, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self.retryUnlocked()
            }
            self?.retryTask = nil
        }
    }

    private func retryUnlocked() {
        for (ref, file) in waitingForExcel where !ExportPaths.isLockedByExcel(file) {
            waitingForExcel[ref] = nil
            // Only closed lessons have a file; a lesson reopened meanwhile is left alone.
            guard let schoolClass = store.schoolClass(ref.classID), !schoolClass.isOpen(ref.lessonID) else { continue }
            switch write(ref) {
            case .exported(let url):
                if !schoolClass.isLast(ref.lessonID) { finalize(ref) }
                notice = Notice(message: "Excel je zavřený, export proběhl: \(url.lastPathComponent)", fileURL: url, isError: false)
            case .failed(let message):
                notice = Notice(message: "Export se nepodařil: \(message)", fileURL: nil, isError: true)
            case .locked:
                break
            }
        }
    }

    private func lesson(_ ref: LessonRef) -> Lesson? {
        store.schoolClass(ref.classID)?.lessons.first { $0.id == ref.lessonID }
    }
}
