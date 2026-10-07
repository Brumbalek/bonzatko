import SwiftUI

@main
struct BonzatkoApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Bonzátko", id: "main") {
            ContentView()
                .environment(appDelegate.store)
                .environment(appDelegate.navigator)
                .environment(appDelegate.exporter)
                .environment(appDelegate.flow)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1000, height: 680)

        Settings {
            SettingsView()
        }
    }
}
