import SwiftUI

struct ContentView: View {
    @Environment(ClassStore.self) private var store
    @State private var selectedClassID: UUID?
    @State private var isCreatingClass = false

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            List(store.classes, selection: $selectedClassID) { schoolClass in
                VStack(alignment: .leading, spacing: 2) {
                    Text(schoolClass.name)
                    Text("\(Czech.students(schoolClass.activeStudents.count)) · \(schoolClass.abbreviation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(schoolClass.id)
            }
            .navigationTitle("Třídy")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .overlay {
                if store.classes.isEmpty {
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
                ClassDetailView(classID: selectedClassID)
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
        .alert("Chyba", isPresented: Binding(get: { store.errorMessage != nil },
                                              set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
