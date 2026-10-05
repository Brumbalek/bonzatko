import SwiftUI

/// Creates a class or edits its name and file-name abbreviation.
struct ClassFormSheet: View {
    enum Mode {
        case create
        case edit(name: String, abbreviation: String)
    }

    let mode: Mode
    let onSave: (_ name: String, _ abbreviation: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var abbreviation = ""
    /// Once the user edits the abbreviation, stop overwriting it from the name.
    @State private var abbreviationEdited = false

    private var isCreating: Bool {
        if case .create = mode { true } else { false }
    }

    private var canSave: Bool {
        !Names.clean(name).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isCreating ? "Nová třída" : "Upravit třídu")
                .font(.title2.bold())

            Form {
                TextField("Název třídy", text: $name, prompt: Text("např. Úvod do marketingu"))
                    .onChange(of: name) {
                        if !abbreviationEdited {
                            abbreviation = Abbreviation.make(from: name)
                        }
                    }
                TextField("Zkratka pro soubory", text: Binding(
                    get: { abbreviation },
                    set: { abbreviation = $0; abbreviationEdited = true }
                ))
                Text("Používá se v názvech exportů, např. \(Abbreviation.sanitize(abbreviation))_Hodina\(LessonNaming.dateStamp(.now)).xlsx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Zrušit", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isCreating ? "Založit" : "Uložit") {
                    onSave(name, abbreviation)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if case let .edit(currentName, currentAbbreviation) = mode {
                name = currentName
                abbreviation = currentAbbreviation
                abbreviationEdited = true
            }
        }
    }
}
