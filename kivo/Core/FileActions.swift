import AppKit

/// Finder actions on a file Kivo is reporting.
///
/// A cleaner asks to be trusted with files, so being able to go and look at
/// one before acting on it is not a convenience: it is how someone checks
/// the app is telling the truth.
enum FileActions {

    static func reveal(_ url: URL) {

        guard FileManager.default.fileExists(atPath: url.path) else { return }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ url: URL) {

        guard FileManager.default.fileExists(atPath: url.path) else { return }

        NSWorkspace.shared.open(url)
    }

    /// Copies the path, which is what people actually want when a file is
    /// somewhere long and nested.
    static func copyPath(_ url: URL) {

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}
