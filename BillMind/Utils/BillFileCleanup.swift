import Foundation

/// Removes receipt and Mind image files from disk when their owning records are
/// deleted. SwiftData's cascade delete removes `BillRecord` rows but never the
/// JPEGs they reference in the Documents directory, nor a journal's `minds/<id>`
/// folder — without this, deleting journals leaks image files indefinitely.
///
/// Foundation-only and parameterized by plain values (not SwiftData models) so it
/// stays unit-testable: callers gather the paths/ids from the model first, then
/// hand them here.
enum BillFileCleanup {
    /// Override for tests; defaults to the app's Documents directory.
    static func documentsURL(_ fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Delete receipt images stored as Documents-relative filenames.
    static func removeBillImages(_ relativePaths: [String], in directory: URL? = nil, fileManager: FileManager = .default) {
        let dir = directory ?? documentsURL(fileManager)
        for name in relativePaths where !name.isEmpty {
            // Guard against path traversal in stored names; only operate on a
            // direct child of the Documents directory.
            let last = (name as NSString).lastPathComponent
            guard last == name else { continue }
            try? fileManager.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Delete a journal's Mind image directory (`minds/<journalID>`).
    static func removeMindDirectory(journalID: UUID, in directory: URL? = nil, fileManager: FileManager = .default) {
        let dir = directory ?? documentsURL(fileManager)
        let mindDir = dir.appendingPathComponent("minds/\(journalID.uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: mindDir)
    }

    /// Full cleanup for a journal about to be deleted: every bill's images plus the
    /// Mind directory. Pass the values gathered from the model *before* deleting it.
    static func cleanUp(billImagePaths: [String], journalID: UUID, in directory: URL? = nil, fileManager: FileManager = .default) {
        removeBillImages(billImagePaths, in: directory, fileManager: fileManager)
        removeMindDirectory(journalID: journalID, in: directory, fileManager: fileManager)
    }
}
