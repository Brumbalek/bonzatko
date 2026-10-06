import SwiftUI

/// Shows the statuses edited in Excel; they are taken over together or not at all.
struct SyncReviewSheet: View {
    let result: SyncResult
    let fileName: String
    @Environment(SyncFlow.self) private var flow

    private var declineExplanation: String {
        flow.purpose == .newLesson
            ? "Nepřevzít: soubor se přepíše daty aplikace."
            : "Nepřevzít: úpravy z Excelu se zahodí a soubor půjde do Koše."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Úpravy z Excelu")
                .font(.title2.bold())
            Text("V souboru \(fileName) se od uzavření Hodiny změnil stav těchto studentů:")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                if !result.changes.isEmpty {
                    Section {
                        ForEach(result.changes) { change in
                            HStack {
                                Text(change.name)
                                Spacer()
                                Text(change.oldStatus.label)
                                    .foregroundStyle(color(change.oldStatus))
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                                Text(change.newStatus.label)
                                    .foregroundStyle(color(change.newStatus))
                                    .fontWeight(.semibold)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Student")
                            Spacer()
                            Text("v aplikaci → v Excelu")
                        }
                    }
                }
                if !result.warnings.isEmpty {
                    Section("Řádky, které nešlo použít") {
                        ForEach(result.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            if !result.changes.isEmpty {
                Text("Převzít změny: zapíšou se do aplikace, včetně vah losování. \(declineExplanation)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Zrušit", role: .cancel) { flow.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if result.changes.isEmpty {
                    Button("Pokračovat") { flow.apply([]) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Nepřevzít") { flow.apply([]) }
                    Button("Převzít změny") { flow.apply(result.changes) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
    }

    private func color(_ status: ExcelStatus) -> Color {
        switch status {
        case .present: .blue
        case .absent: .red
        case .empty: .secondary
        }
    }
}

/// Bottom banner for export messages, with a Finder shortcut.
struct NoticeBanner: View {
    let notice: ExportCenter.Notice
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? .orange : .green)
            Text(notice.message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let url = notice.fileURL {
                Button("Zobrazit ve Finderu") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button("Zavřít", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(maxWidth: 720)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .shadow(radius: 8, y: 2)
        .padding(16)
    }
}
