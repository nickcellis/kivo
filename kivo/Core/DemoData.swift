#if DEBUG
import Foundation
import AppKit
import SwiftUI

/// A fictional Mac, for the pictures in the README.
///
/// Those pictures have to be of something, and the obvious something is
/// whoever is holding the laptop: their file names, their apps, their home
/// folder, published to a public repository and impossible to take back.
/// So Kivo screenshots a Mac that doesn't exist instead. The figures are
/// plausible and the names are invented.
///
/// Debug only. Nothing here is compiled into a release build, and the
/// capture below is the only thing in Kivo that writes a PNG.
enum DemoData {

    static let volume = VolumeInfo(
        total: 994_662_584_320,
        free: 268_301_926_400
    )

    static let categories: [CleanCategory] = [
        .init(kind: .caches, size: 11_240_833_024, items: 1_042),
        .init(kind: .xcodeDerivedData, size: 24_613_453_824, items: 38),
        .init(kind: .coreSimulator, size: 12_440_309_760, items: 14),
        .init(kind: .dockerData, size: 18_253_611_008, items: 9),
        .init(kind: .trash, size: 3_402_260_480, items: 214),
        .init(kind: .pnpmStore, size: 3_221_225_472, items: 6_180),
        .init(kind: .npmCache, size: 1_825_361_920, items: 4_902),
        .init(kind: .logs, size: 412_090_368, items: 328),
        .init(kind: .downloads, size: 8_912_896_000, items: 176),
        .init(kind: .xcodeDocs, size: 2_147_483_648, items: 3)
    ]

    static let apps: [InstalledApp] = [
        app("Xcode", 18_253_611_008, "26.0", "com.apple.dt.Xcode", days: 1),
        app("Blender", 1_395_864_371, "4.2.1", "org.blenderfoundation.blender", days: 46),
        app("Docker", 1_288_490_188, "4.34.2", "com.docker.docker", days: 3),
        app("Figma", 812_646_400, "124.6", "com.figma.Desktop", days: 12),
        app("Slack", 604_012_544, "4.41.0", "com.tinyspeck.slackmacgap", days: 2),
        app("Spotify", 412_090_368, "1.2.46", "com.spotify.client", days: 1),
        app("Cinema Grade", 386_547_056, "2.1", "com.demo.cinemagrade", days: 214),
        app("Panel Studio", 214_748_364, "3.0.2", "com.demo.panelstudio", days: 402)
    ]

    /// Invented vendors. A README picture is not the place to publish a
    /// list of real companies whose files somebody should delete.
    static let orphans: [Orphan] = [
        orphan("com.northgate.notebook", "Group container",
               "Library/Group Containers/K29PLM4RT8.group.com.northgate.notebook",
               283_115_520, days: 412),
        orphan("com.brightsail.studio", "Support files",
               "Library/Application Support/com.brightsail.studio",
               141_557_760, days: 268),
        orphan("com.brightsail.studio.helper", "Container",
               "Library/Containers/com.brightsail.studio.helper",
               2_097_152, days: 268),
        orphan("com.quarrylane.vpn", "Container",
               "Library/Containers/com.quarrylane.vpn", 16_777_216, days: 91),
        orphan("com.quarrylane.vpn.tunnel", "Container",
               "Library/Containers/com.quarrylane.vpn.tunnel", 294_912, days: 91),
        orphan("com.penfold.reader", "Web storage",
               "Library/HTTPStorages/com.penfold.reader", 1_351_680, days: 14),
        orphan("com.penfold.reader", "Preferences",
               "Library/Preferences/com.penfold.reader.plist", 24_576, days: 14),
        orphan("io.tessellate.mapper", "Saved state",
               "Library/Saved Application State/io.tessellate.mapper.savedState",
               65_536, days: 640)
    ]

    static let largeFiles: [LargeFile] = [
        large("Movies/Field Recordings/coastline-4k.mov", 8_589_934_592),
        large("Documents/Archives/site-backup-2025.zip", 4_294_967_296),
        large("Movies/Renders/turntable-final.mp4", 2_684_354_560),
        large("Documents/Datasets/terrain-tiles.sqlite", 1_610_612_736),
        large("Downloads/ubuntu-24.04-desktop.iso", 1_181_116_006)
    ]

    static let duplicates: [DuplicateSet] = [
        dupe("a1", 1_073_741_824, [
            "Movies/Renders/turntable-final.mp4",
            "Desktop/To send/turntable-final.mp4"
        ]),
        dupe("b2", 268_435_456, [
            "Pictures/Shoots/June/cover.tiff",
            "Pictures/Exports/cover.tiff",
            "Desktop/cover.tiff"
        ]),
        dupe("c3", 104_857_600, [
            "Documents/Contracts/terms-v4.pdf",
            "Downloads/terms-v4.pdf"
        ])
    ]

    static let quarantined: [QuarantineEntry] = [
        held("com.brightsail.studio", "Library/Application Support/com.brightsail.studio",
             141_557_760, days: 2),
        held("Caches", "Library/Caches", 11_240_833_024, days: 6)
    ]

    // MARK: Builders

    private static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }

    private static func date(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
    }

    private static func app(
        _ name: String,
        _ size: Int64,
        _ version: String,
        _ id: String,
        days: Int
    ) -> InstalledApp {

        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            name: name,
            size: size,
            version: version,
            bundleID: id,
            lastUsed: date(days)
        )
    }

    private static func orphan(
        _ id: String,
        _ kind: String,
        _ path: String,
        _ size: Int64,
        days: Int
    ) -> Orphan {

        Orphan(
            url: home.appending(path: path),
            identifier: id,
            size: size,
            kind: kind,
            modified: date(days)
        )
    }

    private static func large(_ path: String, _ size: Int64) -> LargeFile {
        LargeFile(url: home.appending(path: path), size: size)
    }

    private static func dupe(
        _ digest: String,
        _ size: Int64,
        _ paths: [String]
    ) -> DuplicateSet {

        DuplicateSet(
            digest: digest,
            size: size,
            files: paths.map { home.appending(path: $0) }
        )
    }

    private static func held(
        _ label: String,
        _ path: String,
        _ size: Int64,
        days: Int
    ) -> QuarantineEntry {

        QuarantineEntry(
            id: UUID(),
            originalPath: home.appending(path: path).path,
            storedName: label,
            size: size,
            label: label,
            date: date(days)
        )
    }
}

/// Turns the demo data into a screenshot and quits.
///
/// Driven by two environment variables so a script can walk the app one
/// page at a time: KIVO_DEMO names the page, KIVO_SHOT the file to write.
/// With neither set — which is every ordinary launch, Debug included —
/// none of this runs.
enum DemoMode {

    static var section: SidebarSection? {

        guard let raw = ProcessInfo.processInfo.environment["KIVO_DEMO"] else {
            return nil
        }

        return SidebarSection(rawValue: raw)
    }

    static func captureWhenReady() {

        guard let path = ProcessInfo.processInfo.environment["KIVO_SHOT"] else {
            return
        }

        // A window that isn't key draws its sidebar greyed out, which
        // makes every screenshot look like a disabled app.
        NSApp.activate(ignoringOtherApps: true)

        // Wait for a window rather than guessing at a delay. A fixed
        // 1.6 seconds was enough on a warm launch and not enough on the
        // first run of a fresh build, where macOS validates the signature
        // first: the capture found no window and quit, silently, which
        // read as "the script is broken".
        attempt(0, writingTo: path)
    }

    private static func attempt(_ count: Int, writingTo path: String) {

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {

            // Not "isVisible": a window launched from a script can be laid
            // out and sized while still ordered out, and waiting for it to
            // become visible waits forever. What matters is that it exists
            // and has been given a size.
            let ready = NSApp.windows.first {
                $0.contentView.map { view in
                    view.bounds.width > 200 && view.bounds.height > 200
                } == true
            }

            guard let window = ready, let view = window.contentView else {

                // 20 seconds, then give up loudly rather than hang a build.
                guard count < 50 else {
                    FileHandle.standardError.write(
                        Data("kivo: no window to capture\n".utf8)
                    )
                    exit(1)
                }

                return attempt(count + 1, writingTo: path)
            }

            // One size for every screenshot, whatever frame the last
            // session left behind, so the README's pictures line up
            // instead of each being whatever the window happened to be.
            let size = ProcessInfo.processInfo.environment["KIVO_SHOT_SIZE"]?
                .split(separator: "x")
                .compactMap { Double($0) }

            window.setContentSize(
                size?.count == 2
                    ? NSSize(width: size![0], height: size![1])
                    : NSSize(width: 1180, height: 760)
            )
            window.makeKeyAndOrderFront(nil)

            // One more beat, for the page transition and the app icons.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {

                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { exit(1) }

                view.cacheDisplay(in: view.bounds, to: rep)

                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))

                exit(0)
            }
        }
    }
}
#endif
