import CryptoKit
import Foundation

nonisolated enum FactorioSaveSync {
    private static let bookmarkKey = "FactorioSaveFolderBookmark"

    private struct SyncState: Codable {
        var folder: String
        var hashes: [String: String]
    }

    static var hasFolder: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    static func saveFolder(_ url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw SyncError.folderAccess
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let bookmark = try url.bookmarkData(options: .minimalBookmark,
            includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    static func synchronize() throws {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        let shared = try URL(resolvingBookmarkData: bookmark, options: [],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        guard shared.startAccessingSecurityScopedResource() else {
            throw SyncError.folderAccess
        }
        defer { shared.stopAccessingSecurityScopedResource() }
        if stale { try saveFolder(shared) }

        let manager = FileManager.default
        let local = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "saves", directoryHint: .isDirectory)
        try synchronize(local: local, shared: shared)
    }

    static func synchronize(local: URL, shared: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: local, withIntermediateDirectories: true)
        guard local.standardizedFileURL != shared.standardizedFileURL else { return }

        var coordinationError: NSError?
        var sharedFiles: [String: URL] = [:]
        var listError: Error?
        NSFileCoordinator().coordinate(readingItemAt: shared, options: [], error: &coordinationError) { url in
            do { sharedFiles = try files(in: url) } catch { listError = error }
        }
        if let coordinationError { throw coordinationError }
        if let listError { throw listError }
        let localFiles = try files(in: local)
        let stateURL = local.deletingLastPathComponent().appendingPathComponent("save-sync-state.json")
        let folder = shared.standardizedFileURL.path
        var state = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(SyncState.self, from: $0) }
            ?? SyncState(folder: folder, hashes: [:])
        if state.folder != folder { state = SyncState(folder: folder, hashes: [:]) }

        func remember(_ name: String, _ hash: String) throws {
            state.hashes[name] = hash
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        }

        for name in Set(localFiles.keys).union(sharedFiles.keys).sorted() {
            let localFile = local.appendingPathComponent(name)
            let sharedFile = shared.appendingPathComponent(name)
            switch (localFiles[name], sharedFiles[name]) {
            case (.some, nil):
                let hash = try fingerprint(localFile).0
                try copy(localFile, to: sharedFile)
                try remember(name, hash)
            case (nil, .some):
                let hash = try fingerprint(sharedFile).0
                try copy(sharedFile, to: localFile)
                try remember(name, hash)
            case (.some, .some):
                let (localHash, localDate) = try fingerprint(localFile)
                let (sharedHash, sharedDate) = try fingerprint(sharedFile)
                if localHash == sharedHash {
                    try remember(name, localHash)
                    continue
                }
                if state.hashes[name] == sharedHash {
                    try copy(localFile, to: sharedFile)
                    try remember(name, localHash)
                    continue
                }
                if state.hashes[name] == localHash {
                    try copy(sharedFile, to: localFile)
                    try remember(name, sharedHash)
                    continue
                }
                let localIsNewer = localDate >= sharedDate
                let older = localIsNewer ? sharedFile : localFile
                let newer = localIsNewer ? localFile : sharedFile
                let origin = localIsNewer ? "Mac" : "iPad"
                let conflictName = uniqueConflictName(for: name, origin: origin, local: local, shared: shared)
                let localConflict = local.appendingPathComponent(conflictName)
                let sharedConflict = shared.appendingPathComponent(conflictName)
                try copy(older, to: localConflict)
                try copy(localConflict, to: sharedConflict)
                try copy(newer, to: older)
                try remember(name, localIsNewer ? localHash : sharedHash)
            case (nil, nil):
                break
            }
        }
    }

    private static func files(in folder: URL) throws -> [String: URL] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return try Dictionary(uniqueKeysWithValues: urls.compactMap { url in
            guard url.pathExtension.lowercased() == "zip" else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return (url.lastPathComponent, url)
        })
    }

    private static func fingerprint(_ file: URL) throws -> (String, Date) {
        var coordinationError: NSError?
        var hash = ""
        var date = Date.distantPast
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var hasher = SHA256()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    hasher.update(data: chunk)
                }
                hash = Data(hasher.finalize()).base64EncodedString()
                date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        return (hash, date)
    }

    private static func copy(_ source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        let exists = FileManager.default.fileExists(atPath: destination.path)
        NSFileCoordinator().coordinate(readingItemAt: source, options: [],
            writingItemAt: destination, options: exists ? .forReplacing : [],
            error: &coordinationError) { readURL, writeURL in
            let temporary = writeURL.deletingLastPathComponent()
                .appendingPathComponent(".FactorioPad-\(UUID().uuidString).tmp")
            do {
                try FileManager.default.copyItem(at: readURL, to: temporary)
                if exists {
                    _ = try FileManager.default.replaceItemAt(writeURL, withItemAt: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: writeURL)
                }
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    private static func uniqueConflictName(for name: String, origin: String,
        local: URL, shared: URL) -> String {
        let stem = (name as NSString).deletingPathExtension
        let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        var candidate = "\(stem) (\(origin) conflict \(date)).zip"
        var number = 2
        while FileManager.default.fileExists(atPath: local.appendingPathComponent(candidate).path)
            || FileManager.default.fileExists(atPath: shared.appendingPathComponent(candidate).path) {
            candidate = "\(stem) (\(origin) conflict \(date) \(number)).zip"
            number += 1
        }
        return candidate
    }

    private enum SyncError: LocalizedError {
        case folderAccess

        var errorDescription: String? {
            "FactorioPad cannot access the selected save folder. Choose it again in Files."
        }
    }
}
