import SwiftUI

@main
struct HelloWorldApp: App {

    /// Single app-level instance. Lifetime matches the process.
    /// Injected into the environment so any view can observe it
    /// without owning it (and without recreating it on view rebuilds).
    private let scanner = BluetoothScanner()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(scanner)
        }
    }
}
