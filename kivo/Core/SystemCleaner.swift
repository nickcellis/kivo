import Foundation

/// What a cleanup did. Failures are counted rather than thrown: one file
/// held open by a running app must not stop the other two hundred.
struct CleanResult: Equatable {

    var removed: Int = 0
    var bytes: Int64 = 0
    var failed: Int = 0

    static func + (lhs: CleanResult, rhs: CleanResult) -> CleanResult {
        CleanResult(
            removed: lhs.removed + rhs.removed,
            bytes: lhs.bytes + rhs.bytes,
            failed: lhs.failed + rhs.failed
        )
    }
}

/// Where removed things go. The Trash is familiar and visible; quarantine
/// remembers the exact path each item came from, which is what an uninstall
/// needs to be reversible.
enum RemovalMode: String, CaseIterable, Identifiable {

    case trash
    case quarantine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trash: "Trash"
        case .quarantine: "Removed Items"
        }
    }

    var note: String {
        switch self {
        case .trash: "Goes to your Trash, where Finder's Put Back works as usual."
        case .quarantine: "Kept inside Kivo, so you can put it back from Removed Items."
        }
    }
}

enum SystemCleaner {

    private static let fm = FileManager.default

    /// Nothing outside the user's own home folder is ever touched, and the
    /// home folder itself is never a target.
    ///
    /// Every path Kivo removes is built from a category's relative path, so
    /// in normal use this can't fire. It exists because the cost of a bug
    /// that makes it fire once is somebody's Mac, and a guard at the point
    /// of deletion is the only one that can't be bypassed by a new caller.
    static func isSafeTarget(_ url: URL, home: URL) -> Bool {

        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        let root = home.standardizedFileURL.resolvingSymlinksInPath().path

        // The home folder, "/" and anything above are all refused.
        guard target != root, target != "/" else { return false }

        return target.hasPrefix(root + "/")
    }

    /// The folder a category clears. The folder itself always stays: macOS
    /// expects ~/Library/Caches to exist, and removing it causes stranger
    /// problems than a full disk.
    static func root(
        for kind: CleanCategory.Kind,
        home: URL? = nil
    ) -> URL {

        let home = home ?? SystemScanner.defaultHome
        return home.appending(path: kind.path)
    }

    /// Clears a category by moving its contents to the Trash.
    ///
    /// Two rules are enforced here rather than in the UI, so no future
    /// screen can get them wrong:
    ///
    /// - **Downloads is refused outright.** Those are the user's own files.
    ///   Kivo measures them and never counts them as cleanable, and it will
    ///   not delete them however it is called.
    /// - **Everything goes to the Trash**, so a mistake costs a drag back.
    ///   The one exception is the Trash itself, which can't be trashed
    ///   again; emptying it is permanent, so it needs `allowPermanent`.
    ///
    /// Only the immediate children of the folder are moved, not every file
    /// underneath. One cache folder per app is a couple of hundred
    /// operations instead of a hundred thousand.
    static func clean(
        _ kind: CleanCategory.Kind,
        home: URL? = nil,
        mode: RemovalMode = .trash,
        quarantine: Quarantine = .shared,
        allowPermanent: Bool = false,
        keeping: Set<URL> = [],
        isCancelled: () -> Bool = { false },
        progress: (Int, Int) -> Void = { _, _ in }
    ) -> CleanResult {

        // The tier is the rule, so a category added later is safe by
        // default rather than removable by default.
        guard kind.tier != .manual else { return CleanResult() }

        let isTrash = kind == .trash
        if isTrash && !allowPermanent { return CleanResult() }

        let folder = root(for: kind, home: home)

        guard isSafeTarget(folder, home: home ?? SystemScanner.defaultHome) else {
            return CleanResult()
        }

        guard let children = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey],
            options: []
        ) else { return CleanResult() }

        // Compared as resolved paths, not as URLs. A directory URL from
        // contentsOfDirectory carries a trailing slash and an unresolved
        // prefix, so it never equals one built by hand, and the exclusion
        // silently does nothing.
        let keepPaths = Set(
            keeping.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        )

        var result = CleanResult()

        for (index, item) in children.enumerated() {

            if isCancelled() { break }

            // Checked per item as well as per folder: a symlink inside a
            // cache directory resolves somewhere else entirely, and moving
            // the link is fine only while its own path is in bounds.
            guard isSafeTarget(item, home: home ?? SystemScanner.defaultHome) else {
                continue
            }

            // Stated as what to keep rather than what to remove: a preview
            // that is still measuring has an incomplete list, and a
            // whitelist built from it would quietly skip whatever hadn't
            // loaded yet. An exclusion list can only ever remove less.
            let itemPath = item.standardizedFileURL.resolvingSymlinksInPath().path
            guard !keepPaths.contains(itemPath) else { continue }

            progress(index, children.count)

            // Measure before removing: afterwards there's nothing to size,
            // and the figure reported has to be what was actually freed.
            let size = SystemScanner.directoryStats(
                at: item,
                isCancelled: isCancelled
            ).size

            do {
                if isTrash {
                    // Emptying the Trash is the permanent case; quarantining
                    // what is already discarded would only move it sideways.
                    try fm.removeItem(at: item)
                } else if mode == .quarantine {
                    try quarantine.store(
                        item,
                        label: kind.rawValue.capitalized,
                        size: size
                    )
                } else {
                    try fm.trashItem(at: item, resultingItemURL: nil)
                }
                result.removed += 1
                result.bytes += size
            } catch {
                result.failed += 1
            }
        }

        return result
    }
}
