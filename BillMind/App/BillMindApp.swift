import SwiftUI
import SwiftData

@main
struct BillMindApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Journal.self, BillRecord.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // If schema migration fails, delete old store and recreate
            print("SwiftData migration failed: \(error). Resetting store.")
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: url)
            container = try! ModelContainer(for: schema, configurations: [config])
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
