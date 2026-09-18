import Foundation

/// One thing Kivo has taken out of the way, and where it came from.
struct QuarantineEntry: Codable, Identifiable, Equatable {

    let id: UUID
    let originalPath: String
    let storedName: String
    let size: Int64
    let label: String
    let date: Date

    var originalURL: URL { URL(fileURLWithPath: originalPath) }
    var name: String { originalURL.lastPathComponent }

    /// Days left before Kivo deletes this for good, or nil when nothing
    /// expires. Shown on the row, because a countdown nobody can see is
    /// just data loss on a timer.
    func daysLeft(
        retention: QuarantineRetention = .current,
        asOf now: Date = Date()
    ) -> Int? {

        guard retention != .never else { return nil }

        let elapsed = now.timeIntervalSince(date) / 86_400
        return max(Int(ceil(Double(retention.rawValue) - elapsed)), 0)
    }

    var shortPath: String {
        originalPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// How long Kivo holds something before deleting it for good.
enum QuarantineRetention: Int, CaseIterable, Identifiable {

    case never = 0
    case week = 7
    case month = 30
    case quarter = 90

    static let storageKey = "quarantineRetentionDays"

    static var current: QuarantineRetention {
        let stored = UserDefaults.standard.object(forKey: storageKey) as? Int
        return stored.flatMap(QuarantineRetention.init(rawValue:)) ?? .month
    }

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .never: "Keep until I delete them"
        case .week: "After 7 days"
        case .month: "After 30 days"
        case .quarter: "After 90 days"
        }
    }

    var shortTitle: String {
        switch self {
        case .never: "Never"
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        }
    }
}

/// A holding area between "removed" and "gone".
///
/// The Trash is the right destination for a folder of caches, but it is the
/// wrong one for an uninstall: an app's files come from a dozen scattered
/// paths, and getting them back matters more than being able to see them in
/// Finder. Quarantine records where every item came from, so restoring puts
/// it back exactly, and purging is a separate decision made later.
final class Quarantine {

    static let shared = Quarantine()

    private let fm = FileManager.default
    private let root: URL

    /// Injectable, so tests never reach the real Application Support.
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Kivo/Quarantine")
    }

    private var manifestURL: URL { root.appending(path: "manifest.json") }
    private var itemsURL: URL { root.appending(path: "Items") }

    // MARK: Reading

    func entries() -> [QuarantineEntry] {

        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([QuarantineEntry].self, from: data)
        else { return [] }

        return entries.sorted { $0.date > $1.date }
    }

    var totalBytes: Int64 {
        entries().reduce(0) { $0 + $1.size }
    }

    /// Where the held copy actually sits, for revealing it in Finder.
    func storedURL(for entry: QuarantineEntry) -> URL {
        itemsURL.appending(path: entry.storedName)
    }

    // MARK: Writing

    /// Moves an item in and records where it came from.
    @discardableResult
    func store(_ url: URL, label: String, size: Int64) throws -> QuarantineEntry {

        try fm.createDirectory(at: itemsURL, withIntermediateDirectories: true)

        let id = UUID()
        // The stored name keeps the original extension so a quarantined
        // .app is still recognisable if someone opens the folder directly.
        let storedName = "\(id.uuidString)-\(url.lastPathComponent)"

        try fm.moveItem(at: url, to: itemsURL.appending(path: storedName))

        let entry = QuarantineEntry(
            id: id,
            originalPath: url.path,
            storedName: storedName,
            size: size,
            label: label,
            date: Date()
        )

        var all = entries()
        all.append(entry)
        try write(all)

        return entry
    }

    /// Puts an item back where it came from. Refuses if something is there
    /// again: a restore must never overwrite a fresh install.
    func restore(_ entry: QuarantineEntry) throws {

        let stored = itemsURL.appending(path: entry.storedName)
        let destination = entry.originalURL

        guard fm.fileExists(atPath: stored.path) else {
            throw QuarantineError.missing
        }

        guard !fm.fileExists(atPath: destination.path) else {
            throw QuarantineError.occupied
        }

        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try fm.moveItem(at: stored, to: destination)
        try write(entries().filter { $0.id != entry.id })
    }

    /// Permanent. The only place in Kivo that destroys anything, and it is
    /// reached by its own button after the user has seen the list.
    func purge(_ entry: QuarantineEntry) throws {

        let stored = itemsURL.appending(path: entry.storedName)

        if fm.fileExists(atPath: stored.path) {
            try fm.removeItem(at: stored)
        }

        try write(entries().filter { $0.id != entry.id })
    }

    /// Items held longer than the retention setting.
    ///
    /// Quarantine is the one place in Kivo that only ever grows: four
    /// different flows put things in and nothing takes them out unless
    /// someone presses Delete. A cleaner that quietly hoards gigabytes is
    /// working against its own purpose, so held items age out the way the
    /// Trash does.
    func expired(
        retention: QuarantineRetention = .current,
        asOf now: Date = Date()
    ) -> [QuarantineEntry] {

        guard retention != .never else { return [] }

        let cutoff = now.addingTimeInterval(-Double(retention.rawValue) * 86_400)
        return entries().filter { $0.date < cutoff }
    }

    /// Returns what it removed, so the app can say so rather than having
    /// files disappear between launches with no explanation.
    @discardableResult
    func purgeExpired(
        retention: QuarantineRetention = .current,
        asOf now: Date = Date()
    ) -> CleanResult {

        var result = CleanResult()

        for entry in expired(retention: retention, asOf: now) {
            do {
                try purge(entry)
                result.removed += 1
                result.bytes += entry.size
            } catch {
                result.failed += 1
            }
        }

        return result
    }

    func purgeAll() throws {
        for entry in entries() {
            try? purge(entry)
        }
    }

    private func write(_ entries: [QuarantineEntry]) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: manifestURL, options: .atomic)
    }
}

enum QuarantineError: LocalizedError {

    case missing
    case occupied

    var errorDescription: String? {
        switch self {
        case .missing: "The quarantined copy is no longer there."
        case .occupied: "Something is already at the original location, so Kivo left it alone."
        }
    }
}
