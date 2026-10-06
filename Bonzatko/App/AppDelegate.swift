import AppKit

/// Owns the app's shared objects. On quit, every open lesson is closed and written to Excel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClassStore()
    let navigator = Navigator()
    private(set) lazy var exporter = ExportCenter(store: store)
    private(set) lazy var flow = SyncFlow(store: store, exporter: exporter, navigator: navigator)

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // The app also hosts the unit tests; never touch real exports then.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return .terminateNow }
        return closeOpenLessonsBeforeQuit() ? .terminateNow : .terminateCancel
    }

    /// Returns `false` when the user decides not to quit; lessons closed for quitting are then reopened.
    private func closeOpenLessonsBeforeQuit() -> Bool {
        let openLessons = store.classes.compactMap { schoolClass -> LessonRef? in
            guard let last = schoolClass.lastLesson, schoolClass.isOpen(last.id) else { return nil }
            return LessonRef(classID: schoolClass.id, lessonID: last.id)
        }
        for ref in openLessons {
            store.closeLastLesson(in: ref.classID)
        }

        var pending = openLessons
        while !pending.isEmpty {
            var problems: [(LessonRef, String)] = []
            for ref in pending {
                switch exporter.write(ref) {
                case .exported: break
                case .locked(let url): problems.append((ref, "\(url.lastPathComponent) – otevřený v Excelu"))
                case .failed(let message): problems.append((ref, message))
                }
            }
            guard !problems.isEmpty else { return true }

            let alert = NSAlert()
            alert.messageText = "Některé Hodiny se nepodařilo uložit do Excelu"
            alert.informativeText = """
            \(problems.map(\.1).joined(separator: "\n"))

            Zavřete soubory v Excelu a klikněte na Zkusit znovu. Pokud ukončíte bez exportu, data zůstanou v bezpečí v aplikaci a Hodiny zůstanou otevřené.
            """
            alert.addButton(withTitle: "Zkusit znovu")
            alert.addButton(withTitle: "Ukončit bez exportu")
            alert.addButton(withTitle: "Neukončovat")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                pending = problems.map(\.0)
            case .alertSecondButtonReturn:
                // Without a file the lesson stays open, as before.
                problems.forEach { store.reopenLastLesson(in: $0.0.classID) }
                return true
            default:
                // Not quitting after all: back to work with open lessons and no files.
                for ref in openLessons {
                    exporter.remove(ref)
                    store.reopenLastLesson(in: ref.classID)
                }
                return false
            }
        }
        return true
    }
}
