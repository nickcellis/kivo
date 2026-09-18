//
//  DuplicateTests.swift
//  kivoTests
//
//  Matching by content is the easy part. These pin the three things that
//  make the result trustworthy: no false matches, no counting a file twice
//  under two names, and no reporting copies that are meant to exist.
//

import Testing
import Foundation
@testable import Kivo

struct DuplicateTests {

    private func makeHome() throws -> URL {

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "kivo-dupes-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    /// Big enough to clear the one megabyte floor.
    private var payload: Data {
        Data((0..<1_200_000).map { UInt8($0 % 251) })
    }

    @Test("Identical contents match, and same-size-but-different does not")
    func matchesByContent() throws {

        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        var different = payload
        different[1_199_999] = 9

        try write(payload, to: home.appending(path: "one/file.bin"))
        try write(payload, to: home.appending(path: "two/copy.bin"))
        try write(different, to: home.appending(path: "two/not-a-copy.bin"))

        let sets = DuplicateFinder.find(home: home)

        #expect(sets.count == 1)
        #expect(sets.first?.files.count == 2)
        #expect(sets.first?.reclaimable == sets.first?.size)
    }

    @Test("A hard link is one file, not a duplicate of itself")
    func hardLinksCountOnce() throws {

        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let original = home.appending(path: "one/file.bin")
        try write(payload, to: original)
        try FileManager.default.linkItem(at: original, to: home.appending(path: "one/link.bin"))

        // Removing a hard link frees nothing, so the pair is not a set.
        #expect(DuplicateFinder.find(home: home).isEmpty)
    }

    @Test("Dependency and build folders are left out")
    func skipsDependencyFolders() throws {

        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        // Two projects with the same package installed is normal, and
        // deleting either copy breaks a build.
        try write(payload, to: home.appending(path: "app-one/node_modules/pkg/index.node"))
        try write(payload, to: home.appending(path: "app-two/node_modules/pkg/index.node"))
        try write(payload, to: home.appending(path: "rust-app/target/debug/artifact.bin"))

        #expect(DuplicateFinder.find(home: home).isEmpty)
    }

    @Test("Files below the threshold are ignored")
    func ignoresSmallFiles() throws {

        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try write(Data(count: 2_000), to: home.appending(path: "a/small.bin"))
        try write(Data(count: 2_000), to: home.appending(path: "b/small.bin"))

        #expect(DuplicateFinder.find(home: home).isEmpty)
    }
}
