//
//  SafetyTests.swift
//  kivoTests
//
//  The rules that stop Kivo damaging a Mac. Every one of these covers a
//  path that moves or deletes real files, so a failure here is not a
//  cosmetic regression.
//

import Testing
import Foundation
@testable import Kivo

/// A throwaway home folder. Nothing in these tests may touch the real one:
/// NSHomeDirectory() ignores $HOME, so the only safe way to test a deleter
/// is to pass the directory in explicitly.
private struct TestHome {

    let root: URL
    let home: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "kivo-tests-\(UUID().uuidString)")
        home = root.appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    @discardableResult
    func makeFile(_ path: String, bytes: Int = 1024) -> URL {
        let url = home.appending(path: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: Data(count: bytes))
        return url
    }

    func makeFolder(_ path: String) -> URL {
        let url = home.appending(path: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appending(path: path).path)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - What Kivo refuses to remove

struct CleanerSafetyTests {

    @Test("Folders left to the user are never removed, even when forced")
    func manualTiersRefuse() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        for kind in CleanCategory.Kind.allCases where kind.tier == .manual {

            test.makeFile("\(kind.path)/keep.bin")

            let result = SystemCleaner.clean(kind, home: test.home, allowPermanent: true)

            #expect(result.removed == 0, "\(kind.title) was removed")
            #expect(test.exists("\(kind.path)/keep.bin"), "\(kind.title) lost a file")
        }
    }

    @Test("Emptying the Trash needs to be asked for explicitly")
    func trashNeedsPermission() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        test.makeFile(".Trash/old.bin")

        #expect(SystemCleaner.clean(.trash, home: test.home).removed == 0)
        #expect(test.exists(".Trash/old.bin"))

        #expect(SystemCleaner.clean(.trash, home: test.home, allowPermanent: true).removed == 1)
        #expect(!test.exists(".Trash/old.bin"))
    }

    @Test("Clearing a category empties it without removing the folder itself")
    func folderSurvives() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        test.makeFile("Library/Caches/app.one/blob.bin")
        test.makeFile("Library/Caches/app.two/blob.bin")

        let result = SystemCleaner.clean(
            .caches,
            home: test.home,
            mode: .quarantine,
            quarantine: Quarantine(root: test.root.appending(path: "q"))
        )

        #expect(result.removed == 2)
        #expect(test.exists("Library/Caches"), "the cache folder itself was removed")
        #expect(!test.exists("Library/Caches/app.one"))
    }

    @Test("Unticked items are kept, and everything else still goes")
    func exclusionsHold() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        for name in ["keep-me", "clear-one", "clear-two"] {
            test.makeFile("Library/Caches/\(name)/blob.bin")
        }

        // The URL the sheet actually hands over comes from a directory
        // listing, which is not equal to one built by hand.
        let listed = try FileManager.default.contentsOfDirectory(
            at: test.home.appending(path: "Library/Caches"),
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        let keep = try #require(listed.first { $0.lastPathComponent == "keep-me" })

        let result = SystemCleaner.clean(
            .caches,
            home: test.home,
            mode: .quarantine,
            quarantine: Quarantine(root: test.root.appending(path: "q")),
            keeping: [keep]
        )

        #expect(result.removed == 2)
        #expect(test.exists("Library/Caches/keep-me"), "an unticked item was removed")
        #expect(!test.exists("Library/Caches/clear-one"))
    }

    @Test("Nothing outside the home folder is ever a target")
    func refusesOutsideHome() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        #expect(!SystemCleaner.isSafeTarget(URL(fileURLWithPath: "/"), home: test.home))
        #expect(!SystemCleaner.isSafeTarget(URL(fileURLWithPath: "/System"), home: test.home))
        #expect(!SystemCleaner.isSafeTarget(URL(fileURLWithPath: "/Users"), home: test.home))
        #expect(!SystemCleaner.isSafeTarget(test.home, home: test.home), "the home folder itself")
        #expect(SystemCleaner.isSafeTarget(test.home.appending(path: "Library"), home: test.home))
    }
}

// MARK: - Uninstalling the right app, and only that app

struct UninstallSafetyTests {

    @Test("A bundle identifier is matched as whole components, never as a substring")
    func matchingIsExact() {

        let id = "com.example.app"

        #expect(AppUninstaller.matches("com.example.app", id))
        #expect(AppUninstaller.matches("com.example.app.helper", id))
        #expect(AppUninstaller.matches("TEAM1234.com.example.app", id))
        #expect(AppUninstaller.matches("com.example.app.plist", id))

        // The one that matters: a different app whose name starts the same.
        #expect(!AppUninstaller.matches("com.example.apples", id))
        #expect(!AppUninstaller.matches("com.example.appliance", id))
    }

    @Test("Identifiers that could escape the Library are rejected")
    func rejectsTraversal() {

        #expect(AppUninstaller.isValidBundleID("com.example.app"))
        #expect(AppUninstaller.isValidBundleID("com.example.app-helper_2"))

        #expect(!AppUninstaller.isValidBundleID("../../../System"))
        #expect(!AppUninstaller.isValidBundleID("com/example/app"))
        #expect(!AppUninstaller.isValidBundleID("com..example"))
        #expect(!AppUninstaller.isValidBundleID(".hidden"))
        #expect(!AppUninstaller.isValidBundleID("noDotsHere"))
        #expect(!AppUninstaller.isValidBundleID(""))
    }

    @Test("Apple's own apps, and anything outside Applications, are protected")
    func protectsSystemApps() {

        let safari = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Safari.app"),
            name: "Safari",
            size: 0,
            bundleID: "com.apple.Safari"
        )
        #expect(AppUninstaller.isProtected(safari))

        let stray = InstalledApp(
            url: URL(fileURLWithPath: "/tmp/Something.app"),
            name: "Something",
            size: 0,
            bundleID: "com.example.something"
        )
        #expect(AppUninstaller.isProtected(stray), "an app outside Applications")

        let ordinary = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Example.app"),
            name: "Example",
            size: 0,
            bundleID: "com.example.app"
        )
        #expect(!AppUninstaller.isProtected(ordinary))
    }

    @Test("A protected app reports no leftovers, so nothing can be selected")
    func protectedAppHasNoPlan() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        test.makeFolder("Library/Application Support/com.apple.Safari")

        let safari = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Safari.app"),
            name: "Safari",
            size: 0,
            bundleID: "com.apple.Safari"
        )

        #expect(AppUninstaller.leftovers(for: safari, home: test.home).isEmpty)
    }
}

// MARK: - Removal is reversible

struct QuarantineTests {

    @Test("An item comes back to the exact path it came from")
    func restoresExactly() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        let quarantine = Quarantine(root: test.root.appending(path: "q"))
        let victim = test.makeFolder("Library/Application Support/com.example.app")

        let entry = try quarantine.store(victim, label: "Example", size: 1024)
        #expect(!test.exists("Library/Application Support/com.example.app"))
        #expect(quarantine.entries().count == 1)

        try quarantine.restore(entry)
        #expect(test.exists("Library/Application Support/com.example.app"))
        #expect(quarantine.entries().isEmpty)
    }

    @Test("Restoring never overwrites something that came back in the meantime")
    func restoreRefusesToOverwrite() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        let quarantine = Quarantine(root: test.root.appending(path: "q"))
        let victim = test.makeFolder("Library/Caches/com.example.app")

        let entry = try quarantine.store(victim, label: "Example", size: 1024)
        test.makeFolder("Library/Caches/com.example.app")

        #expect(throws: QuarantineError.self) {
            try quarantine.restore(entry)
        }
    }

    @Test("Purging removes the held copy and forgets it")
    func purgeClears() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        let quarantine = Quarantine(root: test.root.appending(path: "q"))
        let victim = test.makeFolder("Library/Logs/com.example.app")

        let entry = try quarantine.store(victim, label: "Example", size: 1024)
        try quarantine.purge(entry)

        #expect(quarantine.entries().isEmpty)
        #expect(!test.exists("Library/Logs/com.example.app"))
    }
}

// MARK: - Held items age out

struct RetentionTests {

    private func store(_ quarantine: Quarantine, age days: Int, in home: URL) throws {

        let victim = home.appending(path: "item-\(days)")
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        try quarantine.store(victim, label: "Test", size: 1024)
    }

    @Test("Nothing expires when retention is off")
    func neverExpires() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        let quarantine = Quarantine(root: test.root.appending(path: "q"))
        try store(quarantine, age: 0, in: test.home)

        let future = Date().addingTimeInterval(86_400 * 3650)

        #expect(quarantine.expired(retention: .never, asOf: future).isEmpty)
        #expect(quarantine.purgeExpired(retention: .never, asOf: future).removed == 0)
        #expect(quarantine.entries().count == 1)
    }

    @Test("Items older than the setting are deleted, newer ones are kept")
    func expiresPastTheLimit() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        let quarantine = Quarantine(root: test.root.appending(path: "q"))
        try store(quarantine, age: 0, in: test.home)

        // The entry is stamped now, so the test moves the clock instead.
        let inside = Date().addingTimeInterval(86_400 * 29)
        let past = Date().addingTimeInterval(86_400 * 31)

        #expect(quarantine.expired(retention: .month, asOf: inside).isEmpty)

        let purged = quarantine.purgeExpired(retention: .month, asOf: past)
        #expect(purged.removed == 1)
        #expect(purged.bytes == 1024)
        #expect(quarantine.entries().isEmpty)
    }

    @Test("The countdown shown on a row matches the setting")
    func countdownIsHonest() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        let quarantine = Quarantine(root: test.root.appending(path: "q"))
        try store(quarantine, age: 0, in: test.home)

        let entry = try #require(quarantine.entries().first)

        #expect(entry.daysLeft(retention: .never) == nil)
        #expect(entry.daysLeft(retention: .month, asOf: Date()) == 30)
        #expect(entry.daysLeft(retention: .month, asOf: Date().addingTimeInterval(86_400 * 28)) == 2)
        #expect(entry.daysLeft(retention: .month, asOf: Date().addingTimeInterval(86_400 * 40)) == 0)
    }
}

// MARK: - The archive stays small and never crashes the app

struct ArchiveTests {

    @Test("Everything written is capped")
    func capsHold() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        let archive = KivoArchive(root: test.root.appending(path: "store"))

        var saved = ScanArchive()
        saved.apps = (0..<5_000).map {
            .init(path: "/Applications/App\($0).app", name: "App\($0)",
                  size: 1, version: "1", bundleID: "com.example.a\($0)")
        }
        saved.largeFiles = (0..<5_000).map { .init(path: "/x/\($0)", size: 1) }
        archive.save(saved)

        let back = archive.loadScan()
        #expect(back?.apps.count == 300)
        #expect(back?.largeFiles.count == 50)

        for i in 0..<300 {
            _ = archive.append(CleanEvent(removed: i, bytes: 1, failed: 0, mode: "trash"))
        }
        #expect(archive.events().count == 200)
        #expect(archive.storedBytes < 256 * 1024, "the archive grew beyond 256 KB")
    }

    @Test("A corrupt archive is discarded rather than crashing")
    func survivesCorruption() throws {

        let test = try TestHome()
        defer { test.cleanUp() }

        let root = test.root.appending(path: "store")
        let archive = KivoArchive(root: root)
        archive.save(ScanArchive())

        try Data("{ not json at all".utf8)
            .write(to: root.appending(path: "scan.json"))

        #expect(archive.loadScan() == nil)
        #expect(archive.events().isEmpty)
    }
}
