import Foundation
import AppKit

/// Support files whose app is no longer installed.
struct Orphan: Identifiable, Equatable {

    let url: URL
    let identifier: String
    let size: Int64
    let kind: String
    let modified: Date?

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    var shortPath: String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// Finds what apps leave behind when they are dragged to the Trash.
///
/// The uninstaller maps an app to its files; this asks the same question
/// backwards, and the risk profile is the opposite way round too. There,
/// the user names an app and Kivo finds its files. Here Kivo proposes the
/// files, so a wrong guess is Kivo's fault rather than a misunderstanding,
/// and every rule below exists to make a wrong guess unlikely:
///
/// - Only folders whose name is shaped like a bundle identifier are even
///   considered. "Google" and "MobileSync" are skipped, because there is no
///   honest way to decide who owns them.
/// - Apple's own identifiers are never candidates. Plenty belong to system
///   services with no app in /Applications at all.
/// - Whether an app is installed is asked of LaunchServices rather than of
///   /Applications, so an app on another volume or in a subfolder still
///   counts, and the question is asked of the identifier's ancestors too,
///   so an app covers the helpers and group containers named after it.
/// - Nothing is ever pre-selected in the UI. These are candidates for a
///   person to review, not a list to sweep.
enum OrphanFinder {

    private static let fm = FileManager.default

    /// Where leftovers collect, and what to call them.
    private static let locations: [(path: String, kind: String)] = [
        ("Library/Application Support", "Support files"),
        ("Library/Containers", "Container"),
        ("Library/Group Containers", "Group container"),
        ("Library/Caches", "Cache"),
        ("Library/Logs", "Logs"),
        ("Library/Preferences", "Preferences"),
        ("Library/Preferences/ByHost", "Preferences"),
        ("Library/Saved Application State", "Saved state"),
        ("Library/HTTPStorages", "Web storage"),
        ("Library/WebKit", "Web data"),
        ("Library/Application Scripts", "Scripts"),
        ("Library/LaunchAgents", "Launch agent")
    ]

    // MARK: Identifying

    /// Pulls a bundle identifier out of a file name, or nothing if the name
    /// isn't shaped like one.
    ///
    /// Handles the decorations these folders carry: a ".plist" or
    /// ".savedState" extension, ByHost's trailing hardware UUID, and the
    /// team prefix on a group container ("ABCDE12345.com.example.app").
    static func identifier(from filename: String) -> String? {

        var name = filename

        for suffix in [".plist", ".savedState", ".binarycookies"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }

        // ByHost files end in the machine's UUID.
        if let range = name.range(
            of: "\\.[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$",
            options: [.regularExpression, .caseInsensitive]
        ) {
            name = String(name[..<range.lowerBound])
        }

        // The decorations nest, and not in one fixed order: a group
        // container is "TEAMID1234.group.com.example", the scripts folder
        // beside it is spelled the same way, and other files carry only
        // one of the two. Stripping each once in a fixed order left
        // "group.com.microsoft.shared", whose vendor reads as "group.com"
        // and so matches nothing installed. That put Office's shared
        // container on the list with Office installed.
        var stripping = true

        while stripping {

            stripping = false

            // Both spellings occur: "group.com.example" and
            // "groups.com.apple".
            for prefix in ["groups.", "group."] where name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
                stripping = true
                break
            }

            // A ten character team prefix, as Apple issues them.
            if let dot = name.firstIndex(of: "."),
               name.distance(from: name.startIndex, to: dot) == 10,
               name[..<dot].allSatisfy({ $0.isUppercase || $0.isNumber }) {
                name = String(name[name.index(after: dot)...])
                stripping = true
            }
        }

        guard isIdentifierShaped(name) else { return nil }

        return name
    }

    /// Reverse DNS with at least two dots: "com.example.app" qualifies,
    /// "Google" and "com.example" do not. Two dots rather than one because
    /// single-dot names are more often a folder someone named by hand.
    static func isIdentifierShaped(_ name: String) -> Bool {

        let parts = name.split(separator: ".", omittingEmptySubsequences: false)

        guard parts.count >= 3 else { return false }

        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        )

        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    /// Apple's own, wherever the prefix ends up after the decorations are
    /// stripped: "groups.com.apple.podcasts" is Apple's too.
    static func isApple(_ identifier: String) -> Bool {
        identifier.hasPrefix("com.apple.") || identifier.contains(".com.apple.")
    }

    /// The vendor part of an identifier, "com.docker" for
    /// "com.docker.install".
    static func vendor(of identifier: String) -> String {
        identifier.split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Whether anything still on this Mac lays claim to an identifier.
    ///
    /// Asked of LaunchServices rather than of /Applications, so an app on
    /// another volume or in a subfolder still counts. `vendors` carries the
    /// prefixes of every installed app, which is what stops Docker's
    /// installer cache being offered up while Docker itself is installed:
    /// helpers, updaters and installers have their own identifiers and no
    /// app of their own, so an exact match is not enough.
    static func isInstalled(
        _ identifier: String,
        vendors: Set<String> = []
    ) -> Bool {

        if isApple(identifier) { return true }
        if vendors.contains(vendor(of: identifier)) { return true }

        // Helpers, extensions and group containers hang their identifier
        // off the app's own: "net.whatsapp.WhatsApp.shared" is WhatsApp's
        // shared data, not a leftover. So each ancestor is asked about too,
        // down to the vendor, and an installed app covers everything it
        // spawned. This is the half that works without an app ever being
        // listed, which is why it exists alongside the vendor set.
        var parts = identifier.split(separator: ".")

        while parts.count >= 2 {

            let candidate = parts.joined(separator: ".")

            if NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: candidate) != nil {
                return true
            }

            parts.removeLast()
        }

        return false
    }

    /// Vendor prefixes of everything installed, gathered once per scan.
    static func installedVendors(home: URL? = nil) -> Set<String> {

        var vendors: Set<String> = []

        for app in SystemScanner.installedApps() {
            if let id = app.bundleID ?? AppUninstaller.bundleID(of: app.url) {
                vendors.insert(vendor(of: id))
            }
        }

        // Something running right now is installed, wherever it was
        // launched from: a disk image, a Downloads folder, another volume.
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier {
                vendors.insert(vendor(of: id))
            }
        }

        return vendors
    }

    // MARK: Finding

    static func find(
        home: URL? = nil,
        isCancelled: () -> Bool = { false },
        progress: (String) -> Void = { _ in }
    ) -> [Orphan] {

        let home = home ?? SystemScanner.defaultHome
        var found: [Orphan] = []
        var seen: Set<String> = []
        let vendors = installedVendors(home: home)

        // One app leaves files in several places; the identifier is asked
        // about once and the answer reused.
        var installed: [String: Bool] = [:]

        for (path, kind) in locations {

            if isCancelled() { break }

            let folder = home.appending(path: path)
            progress(path)

            guard let children = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {

                if isCancelled() { break }

                guard let id = identifier(from: child.lastPathComponent),
                      !isApple(id),
                      !seen.contains(child.path)
                else { continue }

                let exists = installed[id] ?? {
                    let result = isInstalled(id, vendors: vendors)
                    installed[id] = result
                    return result
                }()

                guard !exists else { continue }

                seen.insert(child.path)

                let size = SystemScanner.directoryStats(
                    at: child,
                    isCancelled: isCancelled
                ).size

                let resolved = size > 0
                    ? size
                    : Int64((try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                        .totalFileAllocatedSize ?? 0)

                found.append(
                    Orphan(
                        url: child,
                        identifier: id,
                        size: resolved,
                        kind: kind,
                        modified: (try? child.resourceValues(
                            forKeys: [.contentModificationDateKey]
                        ))?.contentModificationDate
                    )
                )
            }
        }

        return found.sorted { $0.size > $1.size }
    }
}
