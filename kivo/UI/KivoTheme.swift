import SwiftUI
import AppKit

// MARK: - Palette
//
// Dark first, with a light variant built from the same roles rather than
// as a second, unrelated design, so the appearance setting still means
// something.

extension Color {

    static func kivo(_ light: Color, _ dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
    }

    /// Window ground. Neutral, not navy: a blue page leaves the blue
    /// accent nothing to be, and the sidebar beside it is already grey.
    static let kivoBackground = kivo(
        Color(red: 0.965, green: 0.965, blue: 0.969),
        Color(red: 0.051, green: 0.051, blue: 0.055)
    )

    /// Card surface — a touch lifted from the ground, never a material.
    /// One step up from the ground, no more. The reference's cards are
    /// barely lighter than the page; the separation comes from the border,
    /// not from the fill.
    static let kivoSurface = kivo(
        .white,
        Color(red: 0.086, green: 0.086, blue: 0.094)
    )

    /// Sidebar ground: a shade below the content area so the split reads
    /// without needing a heavy divider.
    static let kivoSidebar = kivo(
        Color(red: 0.941, green: 0.941, blue: 0.945),
        Color(red: 0.039, green: 0.039, blue: 0.043)
    )

    /// Hairline borders. Cards are defined by their edge, not a shadow.
    static let kivoBorder = kivo(
        Color.black.opacity(0.10),
        Color.white.opacity(0.13)
    )

    /// Quiet fill for tracks, chips and hover.
    static let kivoFill = kivo(
        Color.black.opacity(0.05),
        Color.white.opacity(0.06)
    )

    static let kivoText = kivo(
        Color(red: 0.086, green: 0.086, blue: 0.094),
        Color(red: 0.937, green: 0.937, blue: 0.945)
    )

    static let kivoDim = kivo(
        Color(red: 0.420, green: 0.420, blue: 0.439),
        Color(red: 0.557, green: 0.557, blue: 0.580)
    )

    /// The icon's own blue, taken from the two ends of its gradient so the
    /// app and its Dock tile are the same colour rather than two blues that
    /// nearly match.
    ///
    /// Which end goes where is decided by contrast, not by taste: the deep
    /// end reads 8.7:1 on a white card and the lit end only 3.6:1, while on
    /// the dark card the positions reverse.
    static let kivoAccent = kivo(
        Color(red: 0.071, green: 0.267, blue: 0.659),   // icon, deep end
        Color(red: 0.330, green: 0.580, blue: 1.000)    // icon, lit end
    )

    static let kivoAccentPressed = kivo(
        Color(red: 0.047, green: 0.196, blue: 0.510),
        Color(red: 0.259, green: 0.514, blue: 0.965)
    )

    // Status
    static let kivoGood = Color(red: 0.27, green: 0.78, blue: 0.55)
    static let kivoWarn = Color(red: 0.91, green: 0.71, blue: 0.34)
    static let kivoRisk = Color(red: 0.88, green: 0.39, blue: 0.37)
}

// MARK: - Metrics

enum KivoMetrics {

    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 9
    static let chipRadius: CGFloat = 8

    static let cardPadding: CGFloat = 18
    static let gridSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
    static let pagePadding: CGFloat = 26

    static let navHeight: CGFloat = 46
    static let minTileWidth: CGFloat = 196
    /// Measured, not chosen. The footer's status line used to be the
    /// widest thing here at 174pt and set the column's minimum on its own;
    /// with the short wording the floor is the "Removed Items" row at
    /// 137pt, and 156 gives that room without the column taking space the
    /// content has no use for.
    static let sidebarWidth: CGFloat = 156
}

// MARK: - Typography
//
// Monospace for every label and number, which is what makes the app read
// as an instrument: figures line up column to column, and a value changing
// doesn't reflow the row beside it.

enum KivoFont {

    /// The greeting is the biggest thing on the page by a wide margin and
    /// everything under it is small. That gap is what makes a layout look
    /// deliberate rather than uniformly dense.
    static let pageTitle = Font.system(size: 34, weight: .semibold)

    /// Uppercase micro label that heads each card. 10.5pt rather than the
    /// 9.5 it started at: letter-spaced uppercase monospace is the hardest
    /// thing on the screen to read, and it labels every figure in the app.
    static let label = Font.system(size: 10.5, weight: .bold, design: .monospaced)

    /// The number a card exists to show.
    static let metric = Font.system(size: 34, weight: .medium, design: .monospaced)
    static let metricSmall = Font.system(size: 23, weight: .medium, design: .monospaced)

    static let unit = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let body = Font.system(size: 12.5)
    static let caption = Font.system(size: 11.5)
    static let mono = Font.system(size: 11.5, design: .monospaced)
    static let pill = Font.system(size: 9.5, weight: .bold, design: .monospaced)
    static let nav = Font.system(size: 11.5, weight: .medium)
}

// MARK: - Helpers

extension View {

    func kivoPointerCursor() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
