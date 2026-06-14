import Foundation
import SwiftData

/// Whether a cached row matches the server or has local edits awaiting push.
enum SyncState: String, Codable, Sendable {
    case local    // created or edited on device; needs pushing
    case synced   // matches the server (last known)
}

/// Versioned schema for the SwiftData store.
///
/// Declaring an explicit `VersionedSchema` + `SchemaMigrationPlan` is the
/// prerequisite for evolving the model safely. Previously `BillMindApp` caught
/// *any* container-init failure and deleted the entire store — a silent, total
/// data loss on any schema mismatch. With a versioned schema, additive changes
/// migrate lightweightly, and the app only falls back to recovery for genuine
/// corruption (and even then moves the store aside rather than deleting it).
///
/// When the recording-agent models land (e.g. a `sourceSessionID` on
/// `BillRecord` and an audit-trail blob), add `BillMindSchemaV2` here and a
/// `MigrationStage` describing V1 → V2; do not mutate V1.
enum BillMindSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Journal.self, BillRecord.self, AppSettings.self]
    }
}

/// V2 adds sync metadata (serverID / rowVersion / updatedAt / isDeleted /
/// syncState) to Journal + BillRecord so the local store acts as a cache that
/// reconciles with the server.
///
/// The store is a **disposable cache** — the server is the source of truth — so
/// we deliberately do NOT migrate an old cache: the store file is versioned by
/// name (`Schema.storeName`), so a new schema opens a brand-new empty store and
/// the next sync full-pulls. This sidesteps SwiftData lightweight migration
/// entirely (which crashes CoreData when two VersionedSchemas share model
/// classes) and never risks server data.
enum BillMindSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Journal.self, BillRecord.self, AppSettings.self]
    }

    /// The on-disk cache filename for this schema version. Bump on every schema
    /// change so the old cache is discarded rather than migrated.
    static let storeName = "billmind-cache-v2.store"
}

/// Single current schema; no historical migration (versioned store file instead).
enum BillMindMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BillMindSchemaV2.self]
    }

    static var stages: [MigrationStage] { [] }
}
