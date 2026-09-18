import Foundation
import AppKit

/// A file an app left behind, and what kind of thing it is.
struct Leftover: Identifiable, Equatable {

    let url: URL
    let size: Int64
    let kind: String

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    var shortPath: String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// Everything removing one app would take with it.
struct UninstallPlan {

    let app: InstalledApp
    let bundleID: String?
    let leftovers: [Leftover]

    var totalBytes: Int64 {
        app.size + leftovers.reduce(0) { $0 + $1.size }
    }
}

enum AppUninstaller {

    private static let fm = FileManager.default

    /// Bundle identifiers become file paths, so one containing a slash or
    /// a parent reference would let a crafted app point Kivo at anything on
    /// disk. Reverse DNS only: letters, digits, dots, dashes, underscores.
    static func isValidBundleID(_ id: String) -> Bool {

        guard !id.isEmpty, id.count <= 255, id.contains(".") else { return false }
        guard !id.hasPrefix("."), !id.hasSuffix("."), !id.contains("..") else { return false }

        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"
        )

        return id.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Apps Kivo refuses to uninstall at all.
    ///
    /// Apple's own applications are managed by macOS and some are load
    /// bearing; removing one can leave a Mac unable to update. Anything
    /// outside the two Applications folders is refused on the same
    /// principle: an app bundle somewhere unexpected is not Kivo's to move.
    static func isProtected(_ app: InstalledApp) -> Bool {

        let id = app.bundleID ?? bundleID(of: app.url) ?? ""

        if id.hasPrefix("com.apple.") { return true }

        let path = app.url.standardizedFileURL.path

        let allowedRoots = [
            "/Applications/",
            URL(fileURLWithPath: NSHomeDirectory())
                .appending(path: "Applications").path + "/"
        ]

        return !allowedRoots.contains { path.hasPrefix($0) }
    }

    /// A running app must be quit first: moving a live bundle out from
    /// under macOS leaves it in a state neither Kivo nor the user can see.
    static func isRunning(_ app: InstalledApp) -> Bool {

        guard let id = app.bundleID ?? bundleID(of: app.url) else { return false }

        return !NSRunningApplication
            .runningApplications(withBundleIdentifier: id)
            .isEmpty
    }

    static func bundleID(of app: URL) -> String? {
        SystemScanner.bundleInfo(at: app).identifier
    }

    /// Finds what an app has scattered around the user's Library.
    ///
    /// Matching is deliberately narrow. Every hit is either an exact path
    /// built from the bundle identifier, or a filename whose own dot
    /// separated components start with it. A substring search would let
    /// "com.apple.Safari" pull in "com.apple.SafariTechnologyPreview", and
    /// the cost of a wrong match here is somebody else's data.
    static func leftovers(
        for app: InstalledApp,
        home: URL? = nil,
        isCancelled: () -> Bool = { false }
    ) -> [Leftover] {

        let home = home ?? SystemScanner.defaultHome
        let library = home.appending(path: "Library")

        // Already read during the scan for most apps; falls back to the
        // plist for one built by hand.
        let identifier = app.bundleID ?? bundleID(of: app.url)

        guard let id = identifier, isValidBundleID(id) else { return [] }
        guard !isProtected(app) else { return [] }

        var found: [Leftover] = []
        var seen: Set<String> = []

        func add(_ url: URL, _ kind: String) {

            guard fm.fileExists(atPath: url.path), !seen.contains(url.path) else { return }

            seen.insert(url.path)

            let size = SystemScanner.directoryStats(
                at: url,
                isCancelled: isCancelled
            ).size

            // A plain file returns nothing from a directory walk, so fall
            // back to its own allocated size.
            let resolved = size > 0
                ? size
                : Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                    .totalFileAllocatedSize ?? 0)

            found.append(Leftover(url: url, size: resolved, kind: kind))
        }

        // Exact paths built from the identifier.
        add(library.appending(path: "Application Support/\(id)"), "Support files")
        add(library.appending(path: "Caches/\(id)"), "Cache")
        add(library.appending(path: "Preferences/\(id).plist"), "Preferences")
        add(library.appending(path: "Containers/\(id)"), "Container")
        add(library.appending(path: "Saved Application State/\(id).savedState"), "Saved state")
        add(library.appending(path: "HTTPStorages/\(id)"), "Web storage")
        add(library.appending(path: "HTTPStorages/\(id).binarycookies"), "Cookies")
        add(library.appending(path: "WebKit/\(id)"), "Web data")
        add(library.appending(path: "Cookies/\(id).binarycookies"), "Cookies")
        add(library.appending(path: "Logs/\(id)"), "Logs")
        add(library.appending(path: "LaunchAgents/\(id).plist"), "Launch agent")

        // Folders where the identifier appears as a run of whole components,
        // such as "TEAMID.com.example.app" or "com.example.app.helper".
        let prefixed: [(String, String)] = [
            ("Preferences/ByHost", "Preferences"),
            ("Group Containers", "Group container"),
            ("LaunchAgents", "Launch agent"),
            ("Application Scripts", "Scripts")
        ]

        for (folder, kind) in prefixed {

            let directory = library.appending(path: folder)

            guard let contents = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents where matches(item.lastPathComponent, id) {
                add(item, kind)
            }
        }

        return found.sorted { $0.size > $1.size }
    }

    /// True when the identifier is a run of whole dot separated components
    /// of the filename, so "com.example.app" matches "com.example.app",
    /// "com.example.app.helper" and "TEAM.com.example.app", but never
    /// "com.example.apples".
    static func matches(_ filename: String, _ id: String) -> Bool {

        let name = filename.hasSuffix(".plist")
            ? String(filename.dropLast(6))
            : filename

        if name == id { return true }
        if name.hasPrefix(id + ".") { return true }
        if name.hasSuffix("." + id) { return true }
        return name.contains("." + id + ".")
    }
}
