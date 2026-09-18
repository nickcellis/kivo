//
//  OrphanTests.swift
//  kivoTests
//
//  The leftover finder proposes files rather than being handed them, so a
//  wrong guess here is Kivo's mistake. These pin the rules that keep the
//  guesses conservative.
//

import Testing
import Foundation
@testable import Kivo

struct OrphanTests {

    @Test("Only reverse-DNS names are considered at all")
    func identifierShape() {

        #expect(OrphanFinder.isIdentifierShaped("com.example.app"))
        #expect(OrphanFinder.isIdentifierShaped("dev.warp.Warp-Stable"))

        // Folders people and installers name by hand must never qualify.
        #expect(!OrphanFinder.isIdentifierShaped("Google"))
        #expect(!OrphanFinder.isIdentifierShaped("MobileSync"))
        #expect(!OrphanFinder.isIdentifierShaped("com.example"))
        #expect(!OrphanFinder.isIdentifierShaped("CrashReporter"))
        #expect(!OrphanFinder.isIdentifierShaped(""))
    }

    @Test("The decorations these folders carry are stripped")
    func identifierExtraction() {

        #expect(OrphanFinder.identifier(from: "com.example.app") == "com.example.app")
        #expect(OrphanFinder.identifier(from: "com.example.app.plist") == "com.example.app")
        #expect(OrphanFinder.identifier(from: "com.example.app.savedState") == "com.example.app")
        #expect(OrphanFinder.identifier(from: "group.com.example.app") == "com.example.app")

        // A team prefix is exactly ten uppercase or numeric characters.
        #expect(OrphanFinder.identifier(from: "ABCDE12345.com.example.app") == "com.example.app")

        // ByHost preferences carry the machine's UUID.
        #expect(
            OrphanFinder.identifier(
                from: "com.example.app.01234567-89AB-CDEF-0123-456789ABCDEF.plist"
            ) == "com.example.app"
        )

        #expect(OrphanFinder.identifier(from: "Google") == nil)

        // A group container carries both decorations, in either order, and
        // stripping each once left "group.com.microsoft.shared". Its
        // vendor read as "group.com", which matches nothing installed, so
        // Office's shared container was offered up with Office installed.
        #expect(
            OrphanFinder.identifier(from: "ABCDE12345.group.com.microsoft.shared")
                == "com.microsoft.shared"
        )
        #expect(
            OrphanFinder.identifier(from: "group.ABCDE12345.com.example.app")
                == "com.example.app"
        )
        #expect(OrphanFinder.vendor(of: "com.microsoft.shared") == "com.microsoft")
    }

    @Test("Apple's own files are never candidates, however they are spelled")
    func appleIsProtected() {

        #expect(OrphanFinder.isApple("com.apple.Safari"))
        #expect(OrphanFinder.isApple("com.apple.dt.Xcode"))

        // The spelling that slipped through a first pass: "groups." rather
        // than "group.", which left the identifier as groups.com.apple.…
        #expect(OrphanFinder.identifier(from: "groups.com.apple.podcasts") == "com.apple.podcasts")
        #expect(OrphanFinder.isApple("com.apple.podcasts"))
        #expect(OrphanFinder.isInstalled("com.apple.anything.at.all"))
    }

    @Test("A vendor with an app still installed keeps its helpers")
    func vendorPrefixProtects() {

        #expect(OrphanFinder.vendor(of: "com.docker.install") == "com.docker")
        #expect(OrphanFinder.vendor(of: "com.docker.docker") == "com.docker")

        // Docker Desktop is installed as com.docker.docker, so its
        // installer cache under com.docker.install is not a leftover.
        #expect(OrphanFinder.isInstalled("com.docker.install", vendors: ["com.docker"]))

        // A vendor with nothing installed is not protected by the rule.
        #expect(!OrphanFinder.isInstalled("com.nothinghere.gone", vendors: ["com.docker"]))
    }

    @Test("An app in a folder inside /Applications is still installed")
    func appsOneFolderDown() throws {

        // WhatsApp ships as /Applications/WhatsApp.localized/WhatsApp.app,
        // and a listing that stopped at the top level called it
        // uninstalled. That offered up every net.whatsapp.* container,
        // including the group container holding the message database, for
        // an app the user had open at the time.
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "kivo-apps-\(UUID().uuidString)")

        let top = root.appending(path: "Top.app")
        let nested = root.appending(path: "Vendor.localized/Nested.app")
        let inside = top.appending(path: "Contents/Applications/Embedded.app")

        for url in [top, nested, inside] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        defer { try? fm.removeItem(at: root) }

        let found = Set(SystemScanner.appBundles(in: root).map(\.lastPathComponent))

        #expect(found.contains("Top.app"))
        #expect(found.contains("Nested.app"))

        // An app inside another app belongs to that app, not to the user,
        // so the walk never enters a bundle.
        #expect(!found.contains("Embedded.app"))
    }

    @Test("Leftovers gather by vendor, biggest group first")
    func grouping() throws {

        func orphan(_ id: String, _ size: Int64) -> Orphan {
            Orphan(
                url: URL(fileURLWithPath: "/tmp/\(id)"),
                identifier: id,
                size: size,
                kind: "Container",
                modified: nil
            )
        }

        let groups = OrphanFinder.grouped([
            orphan("com.fabriceleyne.menubarstats", 400),
            orphan("com.fabriceleyne.menubarstats.mbsCPUWidget", 100),
            orphan("com.fabriceleyne.menubarstatshelper", 50),
            orphan("com.operasoftware.Opera", 900)
        ])

        #expect(groups.count == 2)

        // Biggest first, so the row worth acting on leads.
        #expect(groups.first?.vendor == "com.operasoftware")

        let menubar = try #require(groups.first { $0.vendor == "com.fabriceleyne" })

        #expect(menubar.items.count == 3)
        #expect(menubar.size == 550)

        // The widgets an app leaves behind carry their own identifiers, so
        // grouping on anything narrower than the vendor splits one app
        // across several rows. The names are listed biggest first, without
        // repeating one.
        #expect(menubar.apps == ["menubarstats", "menubarstatshelper"])
    }

    @Test("A vendor's freshest file is what the group reports")
    func groupDate() throws {

        let old = Date(timeIntervalSince1970: 1_000_000)
        let recent = Date(timeIntervalSince1970: 2_000_000)

        func orphan(_ id: String, _ modified: Date?) -> Orphan {
            Orphan(
                url: URL(fileURLWithPath: "/tmp/\(id)"),
                identifier: id,
                size: 1,
                kind: "Container",
                modified: modified
            )
        }

        let group = try #require(
            OrphanFinder.grouped([
                orphan("com.example.app", old),
                orphan("com.example.app.helper", recent),
                orphan("com.example.app.widget", nil)
            ]).first
        )

        // A vendor with one recent file is not untouched for years.
        #expect(group.modified == recent)
    }

    @Test("An installed app covers the identifiers hung off its own")
    func ancestorsAreProtected() {

        // Helpers, extensions and group containers are named after the app
        // rather than registered themselves, so LaunchServices knows
        // nothing about "net.whatsapp.WhatsApp.shared" on its own.
        #expect(
            OrphanFinder.isInstalled(
                "net.whatsapp.WhatsApp.shared",
                vendors: ["net.whatsapp"]
            )
        )

        #expect(
            OrphanFinder.isInstalled(
                "com.example.app.ServiceExtension",
                vendors: ["com.example"]
            )
        )

        // The rule is a prefix of the identifier, not a substring of it:
        // a different vendor is still a leftover.
        #expect(
            !OrphanFinder.isInstalled(
                "com.other.app.ServiceExtension",
                vendors: ["com.example"]
            )
        )
    }
}
