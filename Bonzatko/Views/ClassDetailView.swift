import SwiftUI

/// One class: its students (add, rename, remove, restore, import) and its lessons.
struct ClassDetailView: View {
    let classID: UUID
    let onDelete: () -> Void

    @Environment(ClassStore.self) private var store
    @Environment(Navigator.self) private var navigator

    private enum Tab: Hashable { case students, lessons }
    @State private var tab: Tab = .students

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

            if schoolClass.isArchived {
                archivedBanner
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            HStack {
                Picker("Zobrazit", selection: $tab) {
                    Text("Studenti (\(active.count))").tag(Tab.students)
                    Text("Hodiny (\(schoolClass.lessons.count))").tag(Tab.lessons)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                ContinueLessonButton(schoolClass: schoolClass)
                NewLessonButton(schoolClass: schoolClass)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if tab == .lessons {
                LessonListView(schoolClass: schoolClass)
            } else {
                studentList(schoolClass, active: active, removed: removed)
            }
        }
        .toolbar {
            if tab == .students {
                ToolbarItemGroup {
                    Button("Odebrat vybrané", systemImage: "person.badge.minus") {
                        isConfirmingRemoval = true
                    }
                    .disabled(checkedIDs.isEmpty || schoolClass.isArchived)
                    .help("Odebrat zaškrtnuté studenty")

                    Button("Importovat…", systemImage: "square.and.arrow.down") {
                        isImporting = true
                    }
                    .disabled(schoolClass.isArchived)
                    .help("Hromadně přidat studenty z textu nebo souboru")
                }
            }
        }
        .navigationTitle(schoolClass.name)
        .onAppear { isAddFieldFocused = !schoolClass.isArchived }
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

    @ViewBuilder
    private func studentList(_ schoolClass: SchoolClass, active: [Student], removed: [Student]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Přidat studenta", text: $newName, prompt: Text("Napište jméno a stiskněte Enter"))
                    .textFieldStyle(.roundedBorder)
                    .focused($isAddFieldFocused)
                    .onSubmit { addTypedName(schoolClass) }
                Button("Přidat") { addTypedName(schoolClass) }
                    .disabled(Names.clean(newName).isEmpty)
            }
            .disabled(schoolClass.isArchived)
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
                                    .disabled(schoolClass.isArchived)
                                    .help("Vrátit studenta do třídy i s celou historií")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
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
            if !schoolClass.isArchived {
                Button("Upravit třídu…") { isEditingClass = true }
            }
            Menu("Další akce", systemImage: "ellipsis.circle") {
                if schoolClass.isArchived {
                    Button("Obnovit z archivu", systemImage: "tray.and.arrow.up") {
                        store.unarchiveClass(classID)
                    }
                } else {
                    Button("Archivovat", systemImage: "archivebox") {
                        store.archiveClass(classID)
                    }
                }
                Divider()
                Button("Smazat třídu…", systemImage: "trash", role: .destructive, action: onDelete)
            }
            .menuStyle(.button)
            .labelStyle(.iconOnly)
            .fixedSize()
            .help("Archivovat nebo smazat třídu")
        }
    }

    private var archivedBanner: some View {
        HStack {
            Label("Třída je archivovaná. Nelze v ní nic měnit ani losovat.", systemImage: "archivebox")
            Spacer()
            Button("Obnovit z archivu") { store.unarchiveClass(classID) }
        }
        .padding(10)
        .background(.yellow.opacity(0.15), in: .rect(cornerRadius: 8))
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
            .disabled(schoolClass.isArchived)

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
                    .onTapGesture(count: 2) {
                        if !schoolClass.isArchived { startRename(student) }
                    }
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
