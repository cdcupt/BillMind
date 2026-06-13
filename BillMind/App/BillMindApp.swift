import SwiftUI
import SwiftData
import os

@main
struct BillMindApp: App {
    let container: ModelContainer

    private static let logger = Logger(subsystem: "com.billmind.app", category: "persistence")

    init() {
        // Build the schema from the versioned schema's model list. Using the
        // array initializer (the same one the app shipped with) keeps this
        // unambiguous, while the migration plan below drives any future V1→Vn
        // migration.
        let schema = Schema(BillMindSchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: BillMindMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // Recovery of last resort. Unlike the previous behavior, this never
            // deletes user data: it moves the unreadable store aside (so it can be
            // recovered) and starts a fresh one. A real schema change should be
            // handled by a migration stage in BillMindMigrationPlan, not here.
            Self.preserveCorruptStore(reason: error)
            if let recovered = try? ModelContainer(
                for: schema,
                migrationPlan: BillMindMigrationPlan.self,
                configurations: [config]
            ) {
                container = recovered
            } else {
                // The on-disk store could not be opened even after moving it
                // aside. Fall back to an in-memory store so the app launches
                // instead of crashing on every start.
                Self.logger.error("Persistent store unrecoverable; falling back to in-memory store")
                let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try! ModelContainer(
                    for: schema,
                    migrationPlan: BillMindMigrationPlan.self,
                    configurations: [memory]
                )
            }
        }
    }

    /// Move the existing SwiftData store (and its `-wal`/`-shm` sidecars) into a
    /// timestamped backup folder instead of deleting them, so a failed open is
    /// recoverable rather than destructive.
    private static func preserveCorruptStore(reason: Error) {
        let fm = FileManager.default
        let support = URL.applicationSupportDirectory
        let storeURL = support.appending(path: "default.store")
        guard fm.fileExists(atPath: storeURL.path) else { return }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDir = support.appending(path: "RecoveredStores/\(stamp)")
        do {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let src = support.appending(path: "default.store\(suffix)")
                guard fm.fileExists(atPath: src.path) else { continue }
                try? fm.moveItem(at: src, to: backupDir.appending(path: "default.store\(suffix)"))
            }
            UserDefaults.standard.set(backupDir.path, forKey: "lastRecoveredStorePath")
            UserDefaults.standard.set(Date(), forKey: "lastStoreRecoveryDate")
            logger.error("SwiftData open failed (\(reason.localizedDescription, privacy: .public)); store moved to \(backupDir.path, privacy: .public)")
        } catch {
            // If even the move fails, leave the store untouched. The caller's
            // in-memory fallback still lets the app launch.
            logger.error("SwiftData open failed and store could not be moved aside: \(error.localizedDescription, privacy: .public)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
