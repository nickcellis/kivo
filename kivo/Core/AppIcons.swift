import AppKit
import SwiftUI

/// Real Finder icons for apps and documents.
///
/// `NSWorkspace.icon(forFile:)` hits the icon services each time, which is
/// fine once and wasteful in a list that redraws on every hover, so results
/// are kept by path. Main actor only, which is where view bodies run.
@MainActor
enum AppIcons {

    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {

        if let hit = cache[url.path] { return hit }

        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = image
        return image
    }

    /// Paths come and go as things are cleaned, so the cache is cleared
    /// after a scan rather than growing for the life of the process.
    static func forget() {
        cache.removeAll()
    }
}
