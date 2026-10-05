import SwiftUI
import UniformTypeIdentifiers

/// Bulk import: pasted text or a file → (column choice for tables) → editable preview → confirm.
struct ImportSheet: View {
    let classID: UUID

    @Environment(ClassStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Step { case source, table, review }
    private enum SourceKind: Hashable { case text, file }

    @State private var step: Step = .source
    @State private var sourceKind: SourceKind = .text
    @State private var pastedText = ""
    @State private var isPickingFile = false
    @State private var errorMessage: String?

    @State private var tables: [ImportTable] = []
    @State private var sheetIndex = 0
    @State private var selectedColumns: [Int] = []
    @State private var firstRowIsHeader = true

    @State private var candidates: [ImportCandidate] = []

    private static let allowedTypes: [UTType] = [
        .plainText, .commaSeparatedText,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "xlsx") ?? .data,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import studentů")
                .font(.title2.bold())

            switch step {
            case .source: sourceStep
            case .table: tableStep
            case .review: reviewStep
            }
        }
        .padding(20)
        .frame(width: 680, height: 560)
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: Self.allowedTypes) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert("Import se nepodařil", isPresented: Binding(get: { errorMessage != nil },
                                                          set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Step 1 – source

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Zdroj", selection: $sourceKind) {
                Text("Vložit text").tag(SourceKind.text)
                Text("Ze souboru").tag(SourceKind.file)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch sourceKind {
            case .text:
                Text("Vložte jména, každé na samostatný řádek.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $pastedText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background.secondary, in: .rect(cornerRadius: 6))
            case .file:
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Podporované soubory: .txt, .docx, .xlsx, .csv")
                        .foregroundStyle(.secondary)
                    Button("Vybrat soubor…") { isPickingFile = true }
                        .controlSize(.large)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Spacer()
                Button("Zrušit", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if sourceKind == .text {
                    Button("Pokračovat") {
                        tables = []
                        review(ImportParser.names(fromText: pastedText))
                    }
                        .keyboardShortcut(.defaultAction)
                        .disabled(ImportParser.names(fromText: pastedText).isEmpty)
                }
            }
        }
    }

    private func load(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            switch try ImportParser.read(url: url) {
            case .names(let names):
                if names.isEmpty {
                    errorMessage = "V souboru nebyla nalezena žádná jména."
                } else {
                    tables = []
                    review(names)
                }
            case .tables(let found):
                let nonEmpty = found.filter { !$0.rows.isEmpty }
                if nonEmpty.isEmpty {
                    errorMessage = "Tabulka v souboru je prázdná."
                } else {
                    tables = nonEmpty
                    sheetIndex = 0
                    selectedColumns = []
                    step = .table
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Step 2 – choose columns

    private var tableStep: some View {
        let table = tables[sheetIndex]
        let previewRows = Array(table.rows.prefix(40).enumerated())

        return VStack(alignment: .leading, spacing: 12) {
            Text("Klikněte na sloupec se jmény. Pokud je jméno a příjmení zvlášť, klikněte na oba sloupce v pořadí, v jakém se mají spojit.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if tables.count > 1 {
                    Picker("List", selection: $sheetIndex) {
                        ForEach(tables.indices, id: \.self) { Text(tables[$0].sheetName).tag($0) }
                    }
                    .frame(maxWidth: 240)
                    .onChange(of: sheetIndex) { selectedColumns = [] }
                }
                Toggle("První řádek je záhlaví", isOn: $firstRowIsHeader)
                Spacer()
                if !selectedColumns.isEmpty {
                    Button("Zrušit výběr") { selectedColumns = [] }
                }
            }

            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(0..<table.columnCount, id: \.self) { column in
                            columnHeader(column)
                        }
                    }
                    ForEach(previewRows, id: \.offset) { index, _ in
                        GridRow {
                            ForEach(0..<table.columnCount, id: \.self) { column in
                                Text(table.cell(index, column))
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .fontWeight(firstRowIsHeader && index == 0 ? .semibold : .regular)
                                    .foregroundStyle(selectedColumns.contains(column) ? Color.primary : Color.secondary)
                                    .background(selectedColumns.contains(column) ? Color.accentColor.opacity(0.15) : .clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { toggleColumn(column) }
                            }
                        }
                        Divider()
                    }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 6))

            HStack {
                if table.rows.count > previewRows.count {
                    Text("Zobrazeno prvních \(previewRows.count) z \(table.rows.count) řádků.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Zpět") { step = .source }
                Button("Pokračovat") {
                    review(ImportParser.names(from: table, columns: selectedColumns, skipFirstRow: firstRowIsHeader))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedColumns.isEmpty)
            }
        }
    }

    private func columnHeader(_ column: Int) -> some View {
        let order = selectedColumns.firstIndex(of: column)
        return Button {
            toggleColumn(column)
        } label: {
            HStack(spacing: 4) {
                Text(ImportParser.columnLetters(column))
                    .bold()
                if let order {
                    Text("\(order + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .background(Color.accentColor, in: .capsule)
                }
            }
            .frame(width: 150, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(order != nil ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
        }
        .buttonStyle(.plain)
    }

    private func toggleColumn(_ column: Int) {
        if let index = selectedColumns.firstIndex(of: column) {
            selectedColumns.remove(at: index)
        } else {
            selectedColumns.append(column)
        }
    }

    // MARK: Step 3 – review names

    private func review(_ names: [String]) {
        candidates = names.map { ImportCandidate(name: $0) }
        step = .review
    }

    private var reviewStep: some View {
        let existing = store.schoolClass(classID)?.students ?? []
        let plan = Dictionary(uniqueKeysWithValues: ImportPlanner.plan(candidates: candidates, existing: existing).map { ($0.candidateID, $0) })
        let importCount = plan.values.filter { $0.finalName != nil }.count
        let conflictCount = plan.values.filter { $0.conflict != .none }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text("Zkontrolujte nalezená jména. Můžete je opravit nebo smazat.")
                .foregroundStyle(.secondary)

            if conflictCount > 0 {
                HStack {
                    Label("\(Czech.names(conflictCount)) už ve třídě je.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Všechny přeskočit") { setAllDuplicates(.skip) }
                    Button("Všechny přidat s rozlišením") { setAllDuplicates(.addDisambiguated) }
                }
            }

            List {
                ForEach($candidates) { $candidate in
                    reviewRow($candidate, plan: plan[candidate.id])
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Text("Importuje se \(Czech.names(importCount)).")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Zpět") { step = tables.isEmpty ? .source : .table }
                Button("Importovat") {
                    let names = ImportPlanner.plan(candidates: candidates, existing: existing).compactMap(\.finalName)
                    store.addStudents(names, to: classID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(importCount == 0)
            }
        }
    }

    private func reviewRow(_ candidate: Binding<ImportCandidate>, plan row: ImportPlanRow?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Jméno", text: candidate.name)
                    .textFieldStyle(.roundedBorder)
                Button("Smazat", systemImage: "trash") {
                    candidates.removeAll { $0.id == candidate.wrappedValue.id }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Odstranit z importu")
            }
            if let row, row.conflict != .none, let alternative = row.disambiguatedName {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(conflictText(row.conflict))
                        .font(.caption)
                    Spacer()
                    Picker("Duplicita", selection: candidate.duplicateChoice) {
                        Text("Přeskočit").tag(DuplicateChoice.skip)
                        Text("Přidat jako „\(alternative)“").tag(DuplicateChoice.addDisambiguated)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func conflictText(_ conflict: ImportPlanRow.Conflict) -> String {
        switch conflict {
        case .none: ""
        case .existingStudent: "Tento student už ve třídě je."
        case .removedStudent: "Takto se jmenuje odebraný student – můžete ho místo importu vrátit."
        case .earlierInImport: "Toto jméno je v importu vícekrát."
        }
    }

    private func setAllDuplicates(_ choice: DuplicateChoice) {
        for index in candidates.indices {
            candidates[index].duplicateChoice = choice
        }
    }
}
