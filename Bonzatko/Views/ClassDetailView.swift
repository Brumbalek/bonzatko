import SwiftUI

/// Student list of one class: add, rename, remove, restore and import.
struct ClassDetailView: View {
    let classID: UUID

    @Environment(ClassStore.self) private var store

    @State private var newName = ""
    @FocusState private var isAddFieldFocused: Bool
    @State private var duplicateName: String?

    @State private var checkedIDs: Set<UUID> = []
    @State private var isConfirmingRemoval = false

    @State private var renamingID: UUID?
    @State private var renameText = ""
    @FocusState private var isRenameFieldFocused: Bool

    @State private var isEditingClass = false
    @State private var isImporting = false
    @State private var showsRemoved = false

    private var schoolClass: SchoolClass? { store.schoolClass(classID) }

    var body: some View {
        if let schoolClass {
            content(schoolClass)
        }
    }

    @ViewBuilder
    private func content(_ schoolClass: SchoolClass) -> some View {
        let active = Names.sortedCzech(schoolClass.activeStudents, by: \.name)
        let removed = Names.sortedCzech(schoolClass.removedStudents, by: \.name)

        VStack(alignment: .leading, spacing: 0) {
            header(schoolClass)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            HStack {
                TextField("Přidat studenta", text: $newName, prompt: Text("Napište jméno a stiskněte Enter"))
                    .textFieldStyle(.roundedBorder)
                    .focused($isAddFieldFocused)
                    .onSubmit { addTypedName(schoolClass) }
                Button("Přidat") { addTypedName(schoolClass) }
                    .disabled(Names.clean(newName).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            List {
                Section {
                    if active.isEmpty {
                        Text("Třída zatím nemá žádné studenty. Přidejte je výše, nebo je importujte ze souboru.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(active) { student in
                        activeRow(student, schoolClass: schoolClass)
                    }
                } header: {
                    Text("Studenti (\(active.count))")
                }

                if !removed.isEmpty {
                    Section {
                        DisclosureGroup("Odebraní studenti (\(removed.count))", isExpanded: $showsRemoved) {
                            ForEach(removed) { student in
                                HStack {
                                    Text(student.name)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Vrátit") {
                                        store.restoreStudent(student.id, in: classID)
                                    }
                                    .help("Vrátit studenta do třídy i s celou historií")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Odebrat vybrané", systemImage: "person.badge.minus") {
                    isConfirmingRemoval = true
                }
                .disabled(checkedIDs.isEmpty)
                .help("Odebrat zaškrtnuté studenty")

                Button("Importovat…", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
                .help("Hromadně přidat studenty z textu nebo souboru")
            }
        }
        .navigationTitle(schoolClass.name)
        .onAppear { isAddFieldFocused = true }
        .confirmationDialog(removalTitle(active), isPresented: $isConfirmingRemoval) {
            Button("Odebrat", role: .destructive) {
                store.removeStudents(checkedIDs, from: classID)
                checkedIDs = []
            }
        } message: {
            Text("Odebraní studenti se už nebudou losovat. Historie jim zůstane a můžete je kdykoli vrátit.")
        }
        .alert("Student už ve třídě je", isPresented: Binding(get: { duplicateName != nil },
                                                              set: { if !$0 { duplicateName = nil } })) {
            if let duplicateName {
                let alternative = Names.disambiguate(duplicateName, takenKeys: Set(schoolClass.students.map { Names.key($0.name) }))
                Button("Přidat jako „\(alternative)“") {
                    store.addStudents([alternative], to: classID)
                    newName = ""
                    isAddFieldFocused = true
                }
                Button("Přeskočit", role: .cancel) {
                    newName = ""
                    isAddFieldFocused = true
                }
            }
        } message: {
            Text(duplicateMessage(schoolClass))
        }
        .sheet(isPresented: $isEditingClass) {
            ClassFormSheet(mode: .edit(name: schoolClass.name, abbreviation: schoolClass.abbreviation)) { name, abbreviation in
                store.updateClass(classID, name: name, abbreviation: abbreviation)
            }
        }
        .sheet(isPresented: $isImporting) {
            ImportSheet(classID: classID)
        }
    }

    private func header(_ schoolClass: SchoolClass) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(schoolClass.name)
                    .font(.largeTitle.bold())
                Text("Zkratka pro soubory: \(schoolClass.abbreviation)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Upravit třídu…") { isEditingClass = true }
        }
    }

    @ViewBuilder
    private func activeRow(_ student: Student, schoolClass: SchoolClass) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { checkedIDs.contains(student.id) },
                set: { isOn in
                    if isOn { checkedIDs.insert(student.id) } else { checkedIDs.remove(student.id) }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            if renamingID == student.id {
                TextField("Jméno", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isRenameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { renamingID = nil }
                    .onChange(of: isRenameFieldFocused) {
                        if !isRenameFieldFocused { commitRename() }
                    }
            } else {
                Text(student.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { startRename(student) }
                    .help("Dvojklikem přejmenujete")
            }
        }
    }

    // MARK: Actions

    private func addTypedName(_ schoolClass: SchoolClass) {
        let name = Names.clean(newName)
        guard !name.isEmpty else { return }
        let row = ImportPlanner.plan(candidates: [ImportCandidate(name: name)], existing: schoolClass.students)[0]
        if row.conflict == .none {
            store.addStudents([name], to: classID)
            newName = ""
            isAddFieldFocused = true
        } else {
            duplicateName = name
        }
    }

    private func startRename(_ student: Student) {
        renameText = student.name
        renamingID = student.id
        isRenameFieldFocused = true
    }

    private func commitRename() {
        guard let renamingID else { return }
        store.renameStudent(renamingID, to: renameText, in: classID)
        self.renamingID = nil
    }

    private func removalTitle(_ active: [Student]) -> String {
        let names = active.filter { checkedIDs.contains($0.id) }.map(\.name)
        if names.count == 1 {
            return "Odebrat studenta „\(names[0])“?"
        }
        return "Odebrat \(Czech.students(names.count))?"
    }

    private func duplicateMessage(_ schoolClass: SchoolClass) -> String {
        guard let duplicateName else { return "" }
        let isRemoved = schoolClass.removedStudents.contains { Names.key($0.name) == Names.key(duplicateName) }
        if isRemoved {
            return "„\(duplicateName)“ je mezi odebranými studenty. Pokud jde o stejného člověka, vraťte ho v seznamu odebraných – zůstane mu historie."
        }
        return "Ve třídě už je student „\(duplicateName)“. Chcete ho přeskočit, nebo přidat s rozlišením?"
    }
}
