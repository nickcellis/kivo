import Foundation
import AppKit

/// Whether macOS will let Kivo read the folders it cares about.
///
/// Desktop, Documents and Downloads are protected by TCC, so touching them
/// raises a system prompt. Without Full Disk Access a scan walks into all
/// three and asks three times, every single scan. Checking first means one
/// decision instead of a stream of dialogs.
enum DiskAccess {

    /// Folders macOS guards individually.
    static let protectedNames = ["Desktop", "Documents", "Downloads"]

    /// True when Kivo can actually read the protected folders.
    ///
    /// Asked by listing one of them, not by probing the TCC database. That
    /// used to be the standard trick, but macOS now refuses TCC.db to every
    /// app including those with Full Disk Access, so it reports "no access"
    /// on a Mac where Desktop, Documents and Downloads all read fine. The
    /// only trustworthy question is the one the app actually needs answered.
    static var hasFullDisk: Bool {

        let home = URL(fileURLWithPath: NSHomeDirectory())

        // Downloads first because it is also a scanned category. Desktop is
        // the fallback for the rare Mac without a Downloads folder.
        for name in ["Downloads", "Desktop"] {

            let folder = home.appending(path: name)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }

            return (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
        }

        return true
    }

    static func isProtected(_ url: URL) -> Bool {

        let home = URL(fileURLWithPath: NSHomeDirectory()).path

        return protectedNames.contains {
            url.path == "\(home)/\($0)" || url.path.hasPrefix("\(home)/\($0)/")
        }
    }

    /// Opens the exact pane, rather than telling someone to go hunting for
    /// it. macOS requires a relaunch after the switch is flipped.
    static func openSettings() {

        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )!

        NSWorkspace.shared.open(url)
    }
}
