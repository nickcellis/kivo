import Foundation

// MARK: - What gets written
//
// Deliberately small records rather than the live model: paths and sizes,
// no icons, no derived text. A full archive on a developer's Mac is tens of
// kilobytes, and the caps below are what keep it there.

struct ScanArchive: Codable {

    /// Bumped when the shape changes. An archive from an older version is
    /// discarded rather than migrated: it is a cache, not user data.
    static let currentVersion = 1

    var version = ScanArchive.currentVersion
    var savedAt = Date()
    var lastScan: Date?
    var scanCount = 0

    var volumeTotal: Int64?
    var volumeFree: Int64?

    var measured: [String] = []
    var categories: [CategoryRecord] = []
    var apps: [AppRecord] = []
    var largeFiles: [FileRecord] = []

    struct CategoryRecord: Codable {
        let kind: String
        let size: Int64
        let items: Int
    }

    struct AppRecord: Codable {
        let path: String
        let name: String
        let size: Int64
        let version: String?
        let bundleID: String?
        var lastUsed: Date?
    }

    struct FileRecord: Codable {
        let path: String
        let size: Int64
    }
}

struct CleanEvent: Codable, Identifiable {

    var id = UUID()
    var date = Date()
    let removed: Int
    let bytes: Int64
    let failed: Int
    let mode: String
}

// MARK: - Archive

/// Writes the last scan and the cleanup log to Application Support.
///
/// Three rules keep the files small and safe: everything is capped, JSON is
/// compact rather than pretty printed, and a file that fails to decode is
/// thrown away instead of crashing the app. None of this is user data. It
/// can always be rebuilt by scanning again.
final class KivoArchive {

    static let shared = KivoArchive()

    /// A developer Mac reaches roughly 50 large files and 300 apps. These
    /// caps stop a pathological machine writing a megabyte of JSON.
    private let maxApps = 300
    private let maxFiles = 50
    private let maxEvents = 200

    private let fm = FileManager.default
    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Kivo")
    }

    private var scanURL: URL { root.appending(path: "scan.json") }
    private var eventsURL: URL { root.appending(path: "cleanups.json") }

    // MARK: Scan

    func loadScan() -> ScanArchive? {

        guard let data = try? Data(contentsOf: scanURL),
              let archive = try? JSONDecoder().decode(ScanArchive.self, from: data),
              archive.version == ScanArchive.currentVersion
        else { return nil }

        return archive
    }

    func save(_ archive: ScanArchive) {

        var trimmed = archive
        trimmed.apps = Array(archive.apps.prefix(maxApps))
        trimmed.largeFiles = Array(archive.largeFiles.prefix(maxFiles))
        trimmed.savedAt = Date()

        write(trimmed, to: scanURL)
    }

    // MARK: Cleanups

    func events() -> [CleanEvent] {

        guard let data = try? Data(contentsOf: eventsURL),
              let events = try? JSONDecoder().decode([CleanEvent].self, from: data)
        else { return [] }

        return events
    }

    /// Append and trim in one step, so the log can't grow without bound
    /// however many cleanups someone runs.
    func append(_ event: CleanEvent) -> [CleanEvent] {

        var all = events()
        all.append(event)

        if all.count > maxEvents {
            all = Array(all.suffix(maxEvents))
        }

        write(all, to: eventsURL)
        return all
    }

    // MARK: Housekeeping

    /// What Kivo has written, for the line in Settings. Excludes quarantine,
    /// which holds real files rather than a cache.
    var storedBytes: Int64 {

        [scanURL, eventsURL].reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    func clear() {
        try? fm.removeItem(at: scanURL)
        try? fm.removeItem(at: eventsURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {

        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            // Compact on purpose: pretty printing this roughly doubles it
            // for a file no one reads by hand.
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            // A cache that can't be written is not worth failing over.
        }
    }
}
