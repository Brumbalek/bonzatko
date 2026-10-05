import SwiftUI

@main
struct BonzatkoApp: App {
    @State private var store = ClassStore()

    var body: some Scene {
        Window("Bonzátko", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1000, height: 680)
    }
}
