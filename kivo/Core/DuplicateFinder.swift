import Foundation
import CryptoKit

/// Files with identical contents, and what keeping them all costs.
struct DuplicateSet: Identifiable, Equatable {

    let digest: String
    let size: Int64
    let files: [URL]

    var id: String { digest }
    var name: String { files.first?.lastPathComponent ?? "" }

    /// Space that would come back if one copy were kept.
    var reclaimable: Int64 { size * Int64(max(files.count - 1, 0)) }
}

/// Finds duplicates by content, not by name.
///
/// Hashing every file would take hours, so the work is staged: group by
/// size first, which is free; hash only the head of files that share a
/// size; and hash in full only what still collides. Most files never get
/// read at all, because nothing else on the disk is exactly their size.
enum DuplicateFinder {

    private static let fm = FileManager.default

    /// Below this, duplicates are not worth a person's attention: a Mac has
    /// thousands of identical tiny files and listing them buries the ones
    /// that matter.
    static let defaultMinimum: Int64 = 1_000_000

    /// Skipped at the top of the home folder. Library is full of caches
    /// that are meant to be copies.
    private static let skippedRoots = ["Library", ".Trash"]

    /// Skipped wherever they appear.
    ///
    /// A developer's Mac is full of identical files inside dependency and
    /// build folders, and they are supposed to be identical: three copies
    /// of React in three projects' node_modules are three projects
    /// working, not 230 MB wasted. Reporting them buries the real
    /// duplicates, and acting on one breaks a build. Package managers own
    /// these folders; a person should not be deleting inside them by hand.
    private static let skippedAnywhere: Set<String> = [
        "node_modules", ".git", "Pods", "Carthage", "vendor",
        ".venv", "venv", ".tox", "DerivedData", ".next", ".nuxt",
        ".gradle", ".cargo", ".rustup", ".npm", ".pnpm-store", ".cache",
        // Build output. Rust's target/ alone accounted for nine of the
        // first ten "duplicates" found on the machine this was written on,
        // all of them intermediate artefacts of one project.
        "target", "build", ".build", "dist", ".turbo", ".parcel-cache"
    ]

    static func find(
        home: URL? = nil,
        minimumBytes: Int64 = defaultMinimum,
        isCancelled: () -> Bool = { false },
        progress: (String) -> Void = { _ in }
    ) -> [DuplicateSet] {

        let home = home ?? SystemScanner.defaultHome

        // MARK: Group by size, which costs nothing

        progress("Listing files")

        var bySize: [Int64: [URL]] = [:]
        var identities: Set<String> = []

        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]

        guard let walker = fm.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants, .skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        for case let file as URL in walker {

            if isCancelled() { return [] }

            let name = file.lastPathComponent

            if skippedAnywhere.contains(name)
                || (skippedRoots.contains(name)
                    && file.deletingLastPathComponent().path == home.path) {
                walker.skipDescendants()
                continue
            }

            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.totalFileAllocatedSize,
                  Int64(size) >= minimumBytes
            else { continue }

            // Hard links and APFS clones are one file wearing two names.
            // Removing the second frees nothing, so they are not duplicates.
            guard let identity = identity(of: file), identities.insert(identity).inserted
            else { continue }

            bySize[Int64(size), default: []].append(file)
        }

        // MARK: Hash the head, then the whole file

        let candidates = bySize.filter { $0.value.count > 1 }
        var sets: [DuplicateSet] = []

        for (size, files) in candidates {

            if isCancelled() { return sets }

            progress("Comparing \(files.count) files of \(size.byteLabel)")

            var byHead: [String: [URL]] = [:]

            for file in files {
                guard let head = digest(of: file, limit: 64 * 1024) else { continue }
                byHead[head, default: []].append(file)
            }

            for (_, sharing) in byHead where sharing.count > 1 {

                if isCancelled() { return sets }

                var byContent: [String: [URL]] = [:]

                for file in sharing {
                    guard let full = digest(of: file) else { continue }
                    byContent[full, default: []].append(file)
                }

                for (hash, identical) in byContent where identical.count > 1 {
                    sets.append(
                        DuplicateSet(
                            digest: hash,
                            size: size,
                            files: identical.sorted { $0.path < $1.path }
                        )
                    )
                }
            }
        }

        return sets.sorted { $0.reclaimable > $1.reclaimable }
    }

    /// Device and inode together: the same pair means the same file on disk.
    private static func identity(of url: URL) -> String? {

        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }

        return "\(info.st_dev)-\(info.st_ino)"
    }

    /// Streams the file so a 4 GB video doesn't become 4 GB of memory.
    private static func digest(of url: URL, limit: Int? = nil) -> String? {

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        var remaining = limit

        while true {

            let chunk = min(remaining ?? 1_048_576, 1_048_576)
            guard chunk > 0, let data = try? handle.read(upToCount: chunk), !data.isEmpty
            else { break }

            hasher.update(data: data)

            if let left = remaining {
                remaining = left - data.count
                if remaining! <= 0 { break }
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
