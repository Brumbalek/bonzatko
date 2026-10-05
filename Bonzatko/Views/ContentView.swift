import SwiftUI

struct ContentView: View {
    @Environment(ClassStore.self) private var store
    @State private var selectedClassID: UUID?
    @State private var isCreatingClass = false
    @State private var showsArchive = false
    @State private var classPendingDeletion: SchoolClass?

    var body: some View {
        @Bindable var store = store
        let current = store.classes.filter { !$0.isArchived }
        let archived = store.classes.filter(\.isArchived)

        NavigationSplitView {
            List(selection: $selectedClassID) {
                Section("Třídy") {
                    ForEach(current) { classRow($0) }
                }
                if !archived.isEmpty {
                    Section("Archiv (\(archived.count))", isExpanded: $showsArchive) {
                        ForEach(archived) { classRow($0) }
                    }
                }
            }
            .navigationTitle("Třídy")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .overlay {
                if current.isEmpty && archived.isEmpty {
                    ContentUnavailableView("Zatím žádné třídy", systemImage: "person.3",
                                           description: Text("Založte první třídu tlačítkem +."))
                }
            }
            .toolbar {
                ToolbarItem {
                    Button("Nová třída", systemImage: "plus") { isCreatingClass = true }
                        .help("Založit novou třídu")
                }
            }
        } detail: {
            if let selectedClassID, store.schoolClass(selectedClassID) != nil {
                ClassDetailView(classID: selectedClassID) {
                    classPendingDeletion = store.schoolClass(selectedClassID)
                }
                .id(selectedClassID)
            } else {
                ContentUnavailableView("Vyberte třídu", systemImage: "sidebar.left",
                                       description: Text("Vlevo vyberte třídu, nebo založte novou."))
            }
        }
        .sheet(isPresented: $isCreatingClass) {
            ClassFormSheet(mode: .create) { name, abbreviation in
                selectedClassID = store.createClass(name: name, abbreviation: abbreviation)
            }
        }
        .confirmationDialog(
            "Smazat třídu „\(classPendingDeletion?.name ?? "")“?",
            isPresented: Binding(get: { classPendingDeletion != nil },
                                 set: { if !$0 { classPendingDeletion = nil } }),
            presenting: classPendingDeletion
        ) { schoolClass in
            Button("Smazat třídu", role: .destructive) {
                if selectedClassID == schoolClass.id { selectedClassID = nil }
                store.deleteClass(schoolClass.id)
            }
        } message: { _ in
            Text("Třída se všemi studenty a historií se přesune do Koše. Exporty v Excelu zůstanou beze změny. Pokud chcete třídu jen schovat, použijte raději Archivovat.")
        }
        .alert("Chyba", isPresented: Binding(get: { store.errorMessage != nil },
                                              set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
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
        .tag(schoolClass.id)
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
}
