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

    var shortPath: String {
        originalPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
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
