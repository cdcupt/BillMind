import SwiftUI
import SwiftData
import os

/// Authentication state for the whole app. Owns the shared APIClient (already
/// wired with the Keychain TokenVault + single-flight refresh) and drives the
/// launch gate: loading → signedOut → signedIn. @MainActor so SwiftUI observes
/// state changes directly.
@MainActor
final class AuthSession: ObservableObject {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(UUID)
    }

    @Published private(set) var state: State = .loading
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false

    private let vault: TokenVault
    private var api: APIClient!

    init(baseURL: URL = APIClient.defaultBaseURL,
         session: URLSession = .shared,
         vault: TokenVault = TokenVault()) {
        self.vault = vault
        self.api = APIClient(baseURL: baseURL, session: session, tokenStore: vault,
                             onSignedOut: { [weak self] in await self?.forceSignedOut() })
    }

    /// The shared, auth-wired client the data slices (sync, capture, stats) use.
    var client: APIClient { api }

    /// Resolve the launch gate from persisted tokens (no network).
    func bootstrap() {
        #if DEBUG
        // UI tests + local visual checks can't complete Sign in with Apple on the
        // simulator, so this bypass enters the signed-in shell directly. DEBUG-only.
        if CommandLine.arguments.contains("--uitesting-signedin") {
            state = .signedIn(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            return
        }
        #endif
        if let uid = vault.userID() { state = .signedIn(uid) } else { state = .signedOut }
    }

    /// Exchange a provider ID token for a session and persist it.
    func signIn(provider: String, idToken: String, nonce: String? = nil) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let tokens = try await api.signIn(provider: provider, idToken: idToken, nonce: nonce)
            await vault.update(tokens)
            state = .signedIn(tokens.userID)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Sign-in failed. Please try again."
        }
    }

    func signOut() async {
        if let refresh = await vault.refreshToken() {
            try? await api.logout(refreshToken: refresh)   // best-effort server revoke
        }
        await vault.clear()
        state = .signedOut
    }

    /// Permanently delete the account on the server (DELETE /v1/account), then
    /// clear the local session. Returns true on success; the caller wipes the
    /// local SwiftData cache. Apple requires in-app account deletion.
    func deleteAccount() async -> Bool {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await api.deleteAccount()
            await vault.clear()
            state = .signedOut
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Couldn't delete your account. Try again."
            return false
        }
    }

    /// Called by the APIClient when a refresh fails — drop to the sign-in gate.
    private func forceSignedOut() async {
        await vault.clear()
        state = .signedOut
    }
}

/// Drives the SyncEngine from the UI: a single in-flight reconcile, surfaced
/// `isSyncing`/`lastError` for pull-to-refresh and a quiet status. Holds its own
/// APIClient backed by the shared Keychain vault, so it stays authed without
/// depending on AuthSession's instance.
@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published var lastError: String?
    @Published private(set) var lastOutcome: SyncOutcome?

    private let engine: SyncEngine

    init(container: ModelContainer, api: SyncAPI) {
        engine = SyncEngine(container: container, api: api)
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            lastOutcome = try await engine.sync()
            lastError = nil
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? "Couldn't sync. Pull to retry."
        }
    }
}

@main
struct BillMindApp: App {
    let container: ModelContainer
    @StateObject private var auth = AuthSession()
    @StateObject private var sync: SyncCoordinator
    @Environment(\.scenePhase) private var scenePhase

    private static let logger = Logger(subsystem: "com.billmind.app", category: "persistence")

    init() {
        #if DEBUG
        // UI tests pass --uitesting-reset to start from an empty store so the
        // create-journal/add-bill E2E is deterministic. DEBUG-only; never ships.
        if CommandLine.arguments.contains("--uitesting-reset") {
            let support = URL.applicationSupportDirectory
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: support.appending(path: "\(BillMindSchemaV2.storeName)\(suffix)"))
            }
            // Skip the first-launch welcome notice so it doesn't derail other E2Es.
            UserDefaults.standard.set(true, forKey: ContentView.welcomeSeenKey)
        }
        #endif

        // Build the schema from the versioned schema's model list. Using the
        // array initializer (the same one the app shipped with) keeps this
        // unambiguous, while the migration plan below drives any future V1→Vn
        // migration.
        // The legacy unversioned cache (default.store) is from the pre-server
        // app; it is disposable (data lives on the server), so delete it rather
        // than migrate. Harmless no-op once it's gone.
        Self.deleteLegacyStore()

        let schema = Schema(BillMindSchemaV2.models)
        // Versioned cache file: a new schema opens a fresh store (the old one is
        // ignored, then cleaned up), so we never run a fragile migration on the
        // disposable cache — sync re-pulls from the server.
        let storeURL = URL.applicationSupportDirectory.appending(path: BillMindSchemaV2.storeName)
        let config = ModelConfiguration(schema: schema, url: storeURL)
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

        // Sync runs against the server using the shared Keychain token vault.
        // Bind to a local so the StateObject autoclosure doesn't capture self.
        let modelContainer = container
        _sync = StateObject(wrappedValue: SyncCoordinator(
            container: modelContainer, api: APIClient(tokenStore: TokenVault())))
    }

    /// Delete the legacy unversioned cache (`default.store` + sidecars). Safe:
    /// the local store is a disposable cache; real data lives on the server.
    private static func deleteLegacyStore() {
        let fm = FileManager.default
        let support = URL.applicationSupportDirectory
        for suffix in ["", "-wal", "-shm"] {
            let legacy = support.appending(path: "default.store\(suffix)")
            if fm.fileExists(atPath: legacy.path) { try? fm.removeItem(at: legacy) }
        }
    }

    /// Move the existing SwiftData store (and its `-wal`/`-shm` sidecars) into a
    /// timestamped backup folder instead of deleting them, so a failed open is
    /// recoverable rather than destructive.
    private static func preserveCorruptStore(reason: Error) {
        let fm = FileManager.default
        let support = URL.applicationSupportDirectory
        let storeName = BillMindSchemaV2.storeName
        let storeURL = support.appending(path: storeName)
        guard fm.fileExists(atPath: storeURL.path) else { return }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDir = support.appending(path: "RecoveredStores/\(stamp)")
        do {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let src = support.appending(path: "\(storeName)\(suffix)")
                guard fm.fileExists(atPath: src.path) else { continue }
                try? fm.moveItem(at: src, to: backupDir.appending(path: "\(storeName)\(suffix)"))
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
                .environmentObject(auth)
                .environmentObject(sync)
                .task { auth.bootstrap() }
                // Sync once signed in, and again whenever the app returns to foreground.
                .task(id: auth.state) {
                    if case .signedIn = auth.state { await sync.sync() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, case .signedIn = auth.state {
                        Task { await sync.sync() }
                    }
                }
        }
        .modelContainer(container)
    }
}
