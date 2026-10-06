import SwiftUI

struct ContentView: View {
    @Environment(ClassStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(ExportCenter.self) private var exporter
    @Environment(SyncFlow.self) private var flow
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
        .modifier(SyncFlowDialogs())
        .overlay(alignment: .bottom) {
            if let notice = exporter.notice {
                NoticeBanner(notice: notice) { exporter.notice = nil }
                    .id(notice.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        guard !notice.isError else { return }
                        try? await Task.sleep(for: .seconds(6))
                        if exporter.notice?.id == notice.id { exporter.notice = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: exporter.notice)
        .confirmationDialog(
            "Smazat Hodinu?",
            isPresented: isPresent($navigator.lessonDeletionRequest),
            presenting: navigator.lessonDeletionRequest
        ) { ref in
            Button("Smazat Hodinu", role: .destructive) {
                flow.deleteLastLesson(in: ref.classID)
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

    private func lessonDeletionMessage(_ ref: LessonRef) -> String {
        guard let schoolClass = store.schoolClass(ref.classID), let lesson = schoolClass.lastLesson else { return "" }
        var message = "Hodina „\(lesson.name)“ se smaže i se všemi výsledky losování. Její případný soubor v Excelu zůstane beze změny."
        if schoolClass.lessons.count > 1 {
            let previous = schoolClass.lessons[schoolClass.lessons.count - 2]
            message += " Hodina „\(previous.name)“ se pak stane poslední a půjde znovu otevřít."
        }
        return message
    }

    private func isPresent<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }
}

/// Dialogs of the new-lesson / export / close flow.
private struct SyncFlowDialogs: ViewModifier {
    @Environment(SyncFlow.self) private var flow

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Založit novou Hodinu?", isPresented: presented { if case .confirmNewLesson = $0 { true } else { false } }) {
                Button("Založit novou Hodinu") { flow.confirmNewLesson() }
                Button("Zrušit", role: .cancel) { flow.cancel() }
            } message: {
                if case .confirmNewLesson(let name) = flow.step {
                    Text("Hodina „\(name)“ se tím definitivně uzavře a už ji nepůjde znovu otevřít, jen prohlížet. Případné úpravy jejího souboru v Excelu vám aplikace teď ukáže. Pozdější úpravy už nenačte – soubor se uzamkne jen pro čtení.")
                }
            }
            .alert("Soubor je otevřený v Excelu", isPresented: presented { if case .excelOpen = $0 { true } else { false } }) {
                Button("Zkusit znovu") { flow.retryReading() }
                Button("Pokračovat bez načtení", role: .destructive) { flow.continueWithoutExcel() }
                Button("Zrušit", role: .cancel) { flow.cancel() }
            } message: {
                if case .excelOpen(let fileName) = flow.step {
                    Text("Uložte a zavřete soubor \(fileName) v Excelu a klikněte na Zkusit znovu. Pokračovat bez načtení použijte, jen když Excel spadl – úpravy ze souboru se nepřevezmou.")
                }
            }
            .alert("Export nelze načíst", isPresented: presented { if case .cannotRead = $0 { true } else { false } }) {
                Button("Pokračovat") { flow.continueWithoutExcel() }
                Button("Zrušit", role: .cancel) { flow.cancel() }
            } message: {
                if case .cannotRead(let message) = flow.step {
                    Text(message)
                }
            }
            .sheet(isPresented: presented { if case .review = $0 { true } else { false } }) {
                if case .review(let result, let fileName) = flow.step {
                    SyncReviewSheet(result: result, fileName: fileName)
                        .interactiveDismissDisabled()
                }
            }
    }

    /// Shown while the step matches; dismissing by other means cancels the flow.
    private func presented(_ matches: @escaping (SyncFlow.Step) -> Bool) -> Binding<Bool> {
        Binding(
            get: { flow.step.map(matches) ?? false },
            set: { isShown in
                if !isShown, let step = flow.step, matches(step) { flow.cancel() }
            }
        )
    }
}
