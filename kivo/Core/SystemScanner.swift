import Foundation
import AppKit
import CoreServices

// MARK: - Results

struct VolumeInfo: Equatable {

    let total: Int64
    let free: Int64

    var used: Int64 { max(total - free, 0) }

    var fraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

/// How much freedom Kivo has with a folder.
enum CleanTier {

    /// Rebuilt automatically, no cost beyond a slower first launch. These
    /// are the only ones counted in "Safe to clean".
    case safe

    /// Kivo can remove it, but you pay to get it back: a re-download, a
    /// rebuild. Never ticked by default.
    case rebuildable

    /// Measured and reported, never removed. Either the files are yours,
    /// or the tool that owns them should do the deleting.
    case manual

    var pill: String {
        switch self {
        case .safe: "Safe"
        case .rebuildable: "Rebuilds"
        case .manual: "Leave to you"
        }
    }
}

struct CleanCategory: Identifiable, Equatable {

    /// Every folder Kivo knows about. Adding one is a case here plus its
    /// row below, and nothing else changes.
    enum Kind: String, CaseIterable {

        case caches
        case logs
        case trash
        case downloads
        case xcodeDerivedData
        case xcodeDocs
        case npmCache
        case pnpmStore
        case coreSimulator
        case dockerData

        /// Path relative to the home folder. Kept here so the scanner and
        /// the cleaner can't disagree about what a category means.
        var path: String {
            switch self {
            case .caches: "Library/Caches"
            case .logs: "Library/Logs"
            case .trash: ".Trash"
            case .downloads: "Downloads"
            case .xcodeDerivedData: "Library/Developer/Xcode/DerivedData"
            case .xcodeDocs: "Library/Developer/Xcode/DocumentationCache"
            case .npmCache: ".npm/_cacache"
            // The store, not ~/Library/pnpm itself: that folder is also
            // pnpm's home, and removing it uninstalls the tool.
            case .pnpmStore: "Library/pnpm/store"
            case .coreSimulator: "Library/Developer/CoreSimulator/Devices"
            case .dockerData: "Library/Containers/com.docker.docker"
            }
        }

        var tier: CleanTier {
            switch self {
            case .caches, .logs, .trash, .xcodeDerivedData, .xcodeDocs, .npmCache: .safe
            case .pnpmStore: .rebuildable
            case .downloads, .coreSimulator, .dockerData: .manual
            }
        }

        var title: String {
            switch self {
            case .caches: "App caches"
            case .logs: "Logs"
            case .trash: "Trash"
            case .downloads: "Downloads"
            case .xcodeDerivedData: "Xcode build files"
            case .xcodeDocs: "Xcode documentation"
            case .npmCache: "npm cache"
            case .pnpmStore: "pnpm store"
            case .coreSimulator: "iOS Simulators"
            case .dockerData: "Docker"
            }
        }

        var icon: String {
            switch self {
            case .caches: "internaldrive.fill"
            case .logs: "doc.text"
            case .trash: "trash"
            case .downloads: "arrow.down.circle"
            case .xcodeDerivedData, .xcodeDocs: "hammer"
            case .npmCache, .pnpmStore: "shippingbox"
            case .coreSimulator: "iphone"
            case .dockerData: "cube.box"
            }
        }

        var detail: String {
            switch self {
            case .caches: "apps rebuild these on their own"
            case .logs: "diagnostic and crash logs"
            case .trash: "already thrown away"
            case .downloads: "files you downloaded"
            case .xcodeDerivedData: "rebuilt next time you build"
            case .xcodeDocs: "re-downloaded when you need it"
            case .npmCache: "packages npm fetches again"
            case .pnpmStore: "shared package store, re-downloaded on install"
            case .coreSimulator: "simulator devices and their data"
            case .dockerData: "images, volumes and settings"
            }
        }

        /// Why Kivo won't touch it, for the categories it won't.
        var manualNote: String? {
            switch self {
            case .downloads:
                "Your own files. Kivo measures them and leaves them alone."
            case .coreSimulator:
                "Deleting these folders by hand confuses Xcode. Use Xcode's Devices window, or run: xcrun simctl delete unavailable"
            case .dockerData:
                "Holds your images and volumes. Reclaim space from Docker Desktop, or run: docker system prune"
            default:
                nil
            }
        }
    }

    let kind: Kind
    let size: Int64
    let items: Int

    var id: String { kind.rawValue }
    var title: String { kind.title }
    var icon: String { kind.icon }
    var detail: String { kind.detail }
    var tier: CleanTier { kind.tier }

    /// Counted in the headline figure, and ticked by default.
    var isSafe: Bool { kind.tier == .safe }

    /// Kivo is willing to remove it at all.
    var isRemovable: Bool { kind.tier != .manual }
}

struct LargeFile: Identifiable, Equatable {

    let url: URL
    let size: Int64

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct InstalledApp: Identifiable, Equatable {

    let url: URL
    let name: String
    let size: Int64
    var version: String?
    var bundleID: String?

    /// When the app was last opened, as far as Spotlight knows. Nil means
    /// there is no record, which is not the same as never opened: on this
    /// Mac 30 of 49 apps have no record while plainly being in use.
    var lastUsed: Date?

    var id: String { url.path }

    /// Only an app with a real date, older than the cutoff, counts as
    /// unused. A missing record must never imply one: telling someone an
    /// app they use daily has been abandoned is how an uninstaller talks
    /// them into deleting something they need.
    func isUnused(asOf now: Date = Date(), months: Int = 6) -> Bool {

        guard let lastUsed else { return false }

        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: now)
        return lastUsed < (cutoff ?? now)
    }

    /// Distinguishes "we don't know" from "we know, and it's recent".
    var hasUsageRecord: Bool { lastUsed != nil }
}

/// The two things Kivo needs out of an app's Info.plist. Read once per app
/// during the scan, so the uninstaller doesn't open the file again.
struct BundleInfo: Equatable {

    var identifier: String?
    var version: String?
}

// MARK: - Scanner

/// Real measurements, not estimates. Everything here is read-only: nothing
/// in Kivo deletes a file yet, by design.
enum SystemScanner {

    private static let fm = FileManager.default

    /// Injectable so tests can point at a temporary directory. It is a
    /// parameter rather than a read of NSHomeDirectory() at each call site
    /// because that function reads the real home from the password
    /// database and ignores $HOME: a test that "redirects" the home by
    /// setting the environment variable silently operates on the user's
    /// own files instead.
    static var defaultHome: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    // MARK: Volume

    static func volumeInfo() -> VolumeInfo? {

        let url = URL(fileURLWithPath: NSHomeDirectory())

        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return nil }

        guard let total = values.volumeTotalCapacity else { return nil }

        let free = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)

        return VolumeInfo(total: Int64(total), free: free)
    }

    // MARK: Directory size

    /// Allocated size on disk, which is what freeing it would actually
    /// return — logical file size overstates it for sparse and compressed
    /// files. Permission errors are skipped rather than aborting the walk:
    /// a cleaner that stops at the first unreadable file reports nothing.
    static func directoryStats(
        at url: URL,
        isCancelled: () -> Bool = { false }
    ) -> (size: Int64, items: Int) {

        guard fm.fileExists(atPath: url.path) else { return (0, 0) }

        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .isRegularFileKey
        ]

        guard let walker = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return (0, 0) }

        var total: Int64 = 0
        var items = 0

        for case let file as URL in walker {

            if isCancelled() { break }

            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }

            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total += Int64(size)
            items += 1
        }

        return (total, items)
    }

    // MARK: Cleanable categories

    static func cleanCategory(
        _ kind: CleanCategory.Kind,
        home: URL? = nil,
        isCancelled: () -> Bool = { false }
    ) -> CleanCategory? {

        let url = SystemCleaner.root(for: kind, home: home ?? defaultHome)

        // A Mac without Xcode shouldn't be shown an empty Xcode row.
        guard fm.fileExists(atPath: url.path) else { return nil }

        let stats = directoryStats(at: url, isCancelled: isCancelled)

        return CleanCategory(kind: kind, size: stats.size, items: stats.items)
    }

    // MARK: Large files

    static func largeFiles(
        minimumBytes: Int64 = 1_000_000_000,
        limit: Int = 50,
        home: URL? = nil,
        skipProtected: Bool = false,
        isCancelled: () -> Bool = { false }
    ) -> [LargeFile] {

        let home = home ?? defaultHome

        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey,
            .isRegularFileKey
        ]

        guard let walker = fm.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            // Skipping package descendants keeps the list to real documents
            // rather than a thousand files inside an .app or .photoslibrary.
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [LargeFile] = []

        for case let file as URL in walker {

            if isCancelled() { break }

            // Stepping into Desktop, Documents or Downloads without Full
            // Disk Access raises a system prompt. Skip the whole subtree
            // rather than asking once per folder, every scan.
            if skipProtected, DiskAccess.isProtected(file) {
                walker.skipDescendants()
                continue
            }

            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.totalFileAllocatedSize,
                  Int64(size) >= minimumBytes
            else { continue }

            found.append(LargeFile(url: file, size: Int64(size)))
        }

        return Array(
            found.sorted { $0.size > $1.size }.prefix(limit)
        )
    }

    // MARK: Bundles

    static func bundleInfo(at app: URL) -> BundleInfo {

        let plist = app.appending(path: "Contents/Info.plist")

        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(
                from: data, format: nil
              ) as? [String: Any]
        else { return BundleInfo() }

        // The short string is the one people recognise ("3.5.1"). Some apps
        // ship only the build number, so fall back rather than show nothing.
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)

        return BundleInfo(
            identifier: info["CFBundleIdentifier"] as? String,
            version: version?.trimmingCharacters(in: .whitespaces)
        )
    }

    // MARK: Last opened

    /// Spotlight's own record, which is what Finder's "Last opened" column
    /// shows. The file system's access date is not a substitute: macOS
    /// touches it for indexing, backups and malware scans, so it reports
    /// apps as recently used when nobody has opened them for years.
    static func lastUsed(at url: URL) -> Date? {

        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }

        let value = MDItemCopyAttribute(item, kMDItemLastUsedDate)
        return value as? Date
    }

    // MARK: Applications

    /// Every app in a folder, including the ones a level down.
    ///
    /// /Applications is not flat. WhatsApp ships inside
    /// "WhatsApp.localized", Utilities is a folder, and several installers
    /// make one of their own. A listing that stops at the top level calls
    /// those apps uninstalled, which is wrong on the Applications page and
    /// dangerous in the leftover finder, where "not installed" is what
    /// offers somebody's files up for removal. One level down is as far as
    /// this goes, and it never enters a bundle: an app inside another app
    /// belongs to that app, not to the user.
    static func appBundles(in root: URL) -> [URL] {

        guard let contents = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var bundles: [URL] = []

        for entry in contents {

            if entry.pathExtension == "app" {
                bundles.append(entry)
                continue
            }

            let isFolder = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false

            guard isFolder else { continue }

            let children = (try? fm.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            bundles.append(contentsOf: children.filter { $0.pathExtension == "app" })
        }

        return bundles
    }

    static func installedApps(
        isCancelled: () -> Bool = { false }
    ) -> [InstalledApp] {

        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Applications")
        ]

        var apps: [InstalledApp] = []

        for root in roots {

            for bundle in appBundles(in: root) {

                if isCancelled() { break }

                let stats = directoryStats(at: bundle, isCancelled: isCancelled)
                let info = bundleInfo(at: bundle)

                apps.append(
                    InstalledApp(
                        url: bundle,
                        name: bundle.deletingPathExtension().lastPathComponent,
                        size: stats.size,
                        version: info.version,
                        bundleID: info.identifier,
                        lastUsed: lastUsed(at: bundle)
                    )
                )
            }
        }

        return apps.sorted { $0.size > $1.size }
    }
}

// MARK: - Formatting

extension Int64 {

    /// Decimal units, matching what Finder and About This Mac report — the
    /// numbers the user can check Kivo against.
    var byteLabel: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
