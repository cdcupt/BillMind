import SwiftUI
import SwiftData

@main
struct BillMindApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Journal.self, BillRecord.self, AppSettings.self])
    }
}
