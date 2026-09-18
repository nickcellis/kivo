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
}
