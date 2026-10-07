import AppKit
import SwiftUI

/// Bonzátko → Nastavení… (Cmd+,)
struct SettingsView: View {
    @AppStorage(SettingsKeys.exportRoot) private var exportRoot = ""
    @AppStorage(SettingsKeys.animationDuration) private var animationDuration = SettingsKeys.defaultAnimationDuration
    @AppStorage(SettingsKeys.soundEnabled) private var soundEnabled = true

    private var exportFolder: URL {
        exportRoot.isEmpty ? ExportPaths.defaultRoot : URL(filePath: exportRoot, directoryHint: .isDirectory)
    }

    var body: some View {
        Form {
            Section("Exporty do Excelu") {
                LabeledContent("Složka") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(exportFolder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        HStack {
                            Button("Vybrat…", action: chooseFolder)
                            Button("Zobrazit ve Finderu") {
                                NSWorkspace.shared.activateFileViewerSelecting([exportFolder])
                            }
                            .disabled(!FileManager.default.fileExists(atPath: exportFolder.path))
                            if !exportRoot.isEmpty {
                                Button("Výchozí") { exportRoot = "" }
                            }
                        }
                    }
                }
                Text("V této složce má každá třída vlastní podsložku. Už uložené soubory zůstanou tam, kde jsou.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Losování") {
                LabeledContent("Délka animace") {
                    HStack {
                        Slider(value: $animationDuration, in: SettingsKeys.animationDurationRange, step: 0.5)
                            .frame(width: 200)
                        Text(animationDuration.formatted(.number.precision(.fractionLength(1))) + " s")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Toggle("Zvuk při losování", isOn: $soundEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Vybrat"
        panel.message = "Vyberte složku, do které se budou ukládat exporty Hodin."
        panel.directoryURL = exportFolder.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            exportRoot = url.path
        }
    }
}

/// Gear button in the window's top bar that opens the settings.
struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Nastavení", systemImage: "gearshape") { openSettings() }
            .help("Nastavení (⌘,)")
    }
}
