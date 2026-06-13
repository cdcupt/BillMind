import Foundation
import SwiftData

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

/// Ordered list of schema versions and the stages that connect them. V1 is the
/// baseline (the current shipping schema), so there are no stages yet.
enum BillMindMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BillMindSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
