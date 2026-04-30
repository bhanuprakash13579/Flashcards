import Foundation
import SwiftData

/// Auto-export the library as JSON into a user-chosen folder (e.g. inside Google Drive,
/// Dropbox, OneDrive — anywhere the iOS Files app shows up). No SDK, no OAuth.
///
/// The trick: we hold a *security-scoped bookmark* to the folder. When the cloud
/// provider syncs that folder, the file gets uploaded automatically.
enum AutoBackupService {

    private static let bookmarkKey = "autoBackup.folderBookmark"
    private static let displayNameKey = "autoBackup.folderName"
    private static let lastBackupKey = "autoBackup.lastBackupDate"
    private static let enabledKey = "autoBackup.enabled"
    private static let backupFilename = "flashcards-backup.json"

    // MARK: - State

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var folderDisplayName: String? {
        UserDefaults.standard.string(forKey: displayNameKey)
    }

    static var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    static var hasFolder: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    // MARK: - Folder selection

    /// Persist a freshly-picked folder URL as a security-scoped bookmark.
    /// Call this from your fileImporter completion when the user picks a folder.
    static func setFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: displayNameKey)
        isEnabled = true
    }

    static func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
        UserDefaults.standard.removeObject(forKey: lastBackupKey)
        isEnabled = false
    }

    /// Resolves the saved bookmark, refreshing it if stale.
    static func resolveFolder() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            // Re-create a fresh bookmark while we have access.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }

    // MARK: - Run

    enum AutoBackupError: Error, LocalizedError {
        case noFolder
        case noAccess
        case write(Error)
        var errorDescription: String? {
            switch self {
            case .noFolder: return "No backup folder selected."
            case .noAccess: return "Could not access the selected folder. Pick it again."
            case .write(let e): return "Write failed: \(e.localizedDescription)"
            }
        }
    }

    /// Snapshot the current library and write it as `flashcards-backup.json` into the saved folder.
    /// Safe to call frequently — it overwrites the same filename so the cloud provider sees one file.
    @discardableResult
    static func runBackup(context: ModelContext) throws -> URL {
        guard isEnabled else { throw AutoBackupError.noFolder }
        guard let folder = try resolveFolder() else { throw AutoBackupError.noFolder }

        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard scoped else { throw AutoBackupError.noAccess }

        let snapshot = try BackupService.snapshot(context: context)
        let data = try BackupService.encode(snapshot)
        let target = folder.appendingPathComponent(backupFilename)

        do {
            try data.write(to: target, options: .atomic)
        } catch {
            throw AutoBackupError.write(error)
        }
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
        return target
    }

    /// Restore by reading `flashcards-backup.json` from the saved folder.
    static func restoreFromAutoBackup(into context: ModelContext,
                                      mode: BackupService.MergeMode) throws -> (decks: Int, cards: Int) {
        guard let folder = try resolveFolder() else { throw AutoBackupError.noFolder }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard scoped else { throw AutoBackupError.noAccess }

        let target = folder.appendingPathComponent(backupFilename)
        return try BackupService.restore(from: target, into: context, mode: mode)
    }
}
