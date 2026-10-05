import SwiftUI

struct ContentView: View {
    @Environment(ClassStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var isCreatingClass = false
    @State private var showsArchive = false
    @State private var classPendingDeletion: SchoolClass?

    var body: some View {
        @Bindable var navigator = navigator

        Group {
            if let ref = navigator.openLesson {
                LessonView(ref: ref)
            } else {
                splitView
            }
        }
        .sheet(isPresented: $isCreatingClass) {
            ClassFormSheet(mode: .create) { name, abbreviation in
                navigator.sidebarSelection = .schoolClass(store.createClass(name: name, abbreviation: abbreviation))
            }
        }
        .sheet(item: $navigator.browsedLesson) { LessonBrowserSheet(ref: $0) }
        .sheet(item: $navigator.lessonRenameRequest) { RenameLessonSheet(ref: $0) }
        .confirmationDialog(
            "Smazat třídu „\(classPendingDeletion?.name ?? "")“?",
            isPresented: isPresent($classPendingDeletion),
            presenting: classPendingDeletion
        ) { schoolClass in
            Button("Smazat třídu", role: .destructive) {
                if navigator.sidebarSelection == .schoolClass(schoolClass.id) { navigator.sidebarSelection = .home }
                store.deleteClass(schoolClass.id)
            }
        } message: { _ in
            Text("Třída se všemi studenty a historií se přesune do Koše. Exporty v Excelu zůstanou beze změny. Pokud chcete třídu jen schovat, použijte raději Archivovat.")
        }
        .confirmationDialog(
            "Založit novou Hodinu?",
            isPresented: isPresent($navigator.newLessonRequest),
            presenting: navigator.newLessonRequest.flatMap(store.schoolClass)
        ) { schoolClass in
            Button("Založit novou Hodinu") { startNewLesson(schoolClass.id) }
        } message: { schoolClass in
            if let last = schoolClass.lastLesson {
                Text("Hodina „\(last.name)“ se tím definitivně uzavře. Půjde už jen prohlížet.")
            }
        }
        .confirmationDialog(
            "Smazat Hodinu?",
            isPresented: isPresent($navigator.lessonDeletionRequest),
            presenting: navigator.lessonDeletionRequest
        ) { ref in
            Button("Smazat Hodinu", role: .destructive) {
                if navigator.openLesson == ref { navigator.openLesson = nil }
                store.deleteLastLesson(in: ref.classID)
            }
        } message: { ref in
            Text(lessonDeletionMessage(ref))
        }
        .alert("Chyba", isPresented: Binding(get: { store.errorMessage != nil },
                                              set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var splitView: some View {
        @Bindable var navigator = navigator
        let current = store.classes.filter { !$0.isArchived }
        let archived = store.classes.filter(\.isArchived)

        return NavigationSplitView {
            List(selection: $navigator.sidebarSelection) {
                Label("Přehled", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.home)
                Section("Třídy") {
                    ForEach(current) { classRow($0) }
                }
                if !archived.isEmpty {
                    Section("Archiv (\(archived.count))", isExpanded: $showsArchive) {
                        ForEach(archived) { classRow($0) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItem {
                    Button("Nová třída", systemImage: "plus") { isCreatingClass = true }
                        .help("Založit novou třídu")
                }
            }
        } detail: {
            switch navigator.sidebarSelection {
            case .schoolClass(let classID) where store.schoolClass(classID) != nil:
                ClassDetailView(classID: classID) {
                    classPendingDeletion = store.schoolClass(classID)
                }
                .id(classID)
            default:
                HomeView()
            }
        }
    }

    private func classRow(_ schoolClass: SchoolClass) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(schoolClass.name)
            Text("\(Czech.students(schoolClass.activeStudents.count)) · \(schoolClass.abbreviation)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(schoolClass.isArchived ? .secondary : .primary)
        .tag(SidebarItem.schoolClass(schoolClass.id))
        .contextMenu {
            if schoolClass.isArchived {
                Button("Obnovit z archivu", systemImage: "tray.and.arrow.up") {
                    store.unarchiveClass(schoolClass.id)
                }
            } else {
                Button("Archivovat", systemImage: "archivebox") {
                    store.archiveClass(schoolClass.id)
                }
            }
            Divider()
            Button("Smazat…", systemImage: "trash", role: .destructive) {
                classPendingDeletion = schoolClass
            }
        }
    }

    private func startNewLesson(_ classID: UUID) {
        // Phase 4 hooks in here: final export of the previous lesson and sync with its edited Excel file.
        if let lessonID = store.createLesson(in: classID) {
            navigator.openLesson = LessonRef(classID: classID, lessonID: lessonID)
        }
    }

    private func lessonDeletionMessage(_ ref: LessonRef) -> String {
        guard let schoolClass = store.schoolClass(ref.classID), let lesson = schoolClass.lastLesson else { return "" }
        var message = "Hodina „\(lesson.name)“ se smaže i se všemi výsledky losování."
        if schoolClass.lessons.count > 1 {
            let previous = schoolClass.lessons[schoolClass.lessons.count - 2]
            message += " Hodina „\(previous.name)“ se pak stane poslední a půjde v ní znovu pokračovat."
        }
        return message
    }

    private func isPresent<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }
}
