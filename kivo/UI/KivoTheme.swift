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

    /// Window ground.
    static let kivoBackground = kivo(
        Color(red: 0.97, green: 0.965, blue: 0.95),
        Color(red: 0.055, green: 0.086, blue: 0.133)
    )

    /// Card surface — a touch lifted from the ground, never a material.
    static let kivoSurface = kivo(
        .white,
        Color(red: 0.086, green: 0.129, blue: 0.188)
    )

    /// Sidebar ground: a shade below the content area so the split reads
    /// without needing a heavy divider.
    static let kivoSidebar = kivo(
        Color(red: 0.925, green: 0.937, blue: 0.953),
        Color(red: 0.035, green: 0.055, blue: 0.086)
    )

    /// Hairline borders. Cards are defined by their edge, not a shadow.
    static let kivoBorder = kivo(
        Color.black.opacity(0.09),
        Color.white.opacity(0.07)
    )

    /// Quiet fill for tracks, chips and hover.
    static let kivoFill = kivo(
        Color.black.opacity(0.05),
        Color.white.opacity(0.06)
    )

    static let kivoText = kivo(
        Color(red: 0.086, green: 0.122, blue: 0.180),
        Color(red: 0.898, green: 0.925, blue: 0.965)
    )

    static let kivoDim = kivo(
        Color(red: 0.388, green: 0.435, blue: 0.510),
        Color(red: 0.525, green: 0.592, blue: 0.682)
    )

    /// Blue. Cool enough to stay clear of the amber and red that carry
    /// meaning below, so the accent never reads as a status.
    static let kivoAccent = kivo(
        Color(red: 0.13, green: 0.40, blue: 0.86),
        Color(red: 0.36, green: 0.62, blue: 1.00)
    )

    static let kivoAccentPressed = kivo(
        Color(red: 0.10, green: 0.32, blue: 0.72),
        Color(red: 0.28, green: 0.52, blue: 0.90)
    )

    // Status
    static let kivoGood = Color(red: 0.27, green: 0.78, blue: 0.55)
    static let kivoWarn = Color(red: 0.91, green: 0.71, blue: 0.34)
    static let kivoRisk = Color(red: 0.88, green: 0.39, blue: 0.37)
}

// MARK: - Metrics

enum KivoMetrics {

    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 7
    static let chipRadius: CGFloat = 7

    static let cardPadding: CGFloat = 14
    static let gridSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 14
    static let pagePadding: CGFloat = 18

    static let navHeight: CGFloat = 46
    static let minTileWidth: CGFloat = 178
}

// MARK: - Typography
//
// Monospace for every label and number, which is what makes the app read
// as an instrument: figures line up column to column, and a value changing
// doesn't reflow the row beside it.

enum KivoFont {

    static let pageTitle = Font.system(size: 17, weight: .semibold)

    /// Uppercase micro label that heads each card. 10.5pt rather than the
    /// 9.5 it started at: letter-spaced uppercase monospace is the hardest
    /// thing on the screen to read, and it labels every figure in the app.
    static let label = Font.system(size: 10.5, weight: .bold, design: .monospaced)

    /// The number a card exists to show.
    static let metric = Font.system(size: 26, weight: .medium, design: .monospaced)
    static let metricSmall = Font.system(size: 19, weight: .medium, design: .monospaced)

    static let unit = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let body = Font.system(size: 11.5)
    static let caption = Font.system(size: 10.5)
    static let mono = Font.system(size: 10.5, design: .monospaced)
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
