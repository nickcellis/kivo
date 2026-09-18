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

    /// Card surface. Still defined, because a material needs something
    /// behind it and a sheet presented over a sheet has nothing to blur.
    static let kivoSurface = kivo(
        .white,
        Color(red: 0.086, green: 0.129, blue: 0.188)
    )

    /// Tint laid over a card's material. Without it the blur takes the
    /// colour of whatever is behind the window, and the cards drift as the
    /// wallpaper changes.
    static let kivoGlassTint = kivo(
        Color.white.opacity(0.55),
        Color(red: 0.094, green: 0.129, blue: 0.188).opacity(0.55)
    )

    /// The lit edge along the top of a card. A flat border reads as a box;
    /// one that catches light at the top reads as something with thickness.
    static let kivoGlassHighlight = kivo(
        Color.white.opacity(0.9),
        Color.white.opacity(0.16)
    )

    static let kivoGlassEdge = kivo(
        Color.black.opacity(0.10),
        Color.black.opacity(0.32)
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

// MARK: - Glass

/// A card built the way macOS builds one: a material for the blur, a tint
/// so it keeps its own colour, a lit top edge, and a shadow to sit it off
/// the page.
///
/// The material goes over the window's own background, never over another
/// material. Stacking blurs is what turns translucency into grey soup, and
/// it is the reason this app was flat until now.
struct KivoGlass: ViewModifier {

    var radius: CGFloat = KivoMetrics.cardRadius
    var accent: Color?
    var isRaised: Bool = false

    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    func body(content: Content) -> some View {

        content
            .background {
                shape
                    .fill(.regularMaterial)
                    .overlay(shape.fill(Color.kivoGlassTint))
                    .shadow(
                        color: Color.kivoGlassEdge.opacity(isRaised ? 1 : 0.7),
                        radius: isRaised ? 14 : 8,
                        y: isRaised ? 5 : 3
                    )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: accent.map { [$0.opacity(0.7), $0.opacity(0.25)] }
                            ?? [
                                Color.kivoGlassHighlight,
                                Color.kivoGlassHighlight.opacity(scheme == .dark ? 0.25 : 0.35)
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
    }
}

extension View {

    func kivoGlass(
        radius: CGFloat = KivoMetrics.cardRadius,
        accent: Color? = nil,
        isRaised: Bool = false
    ) -> some View {
        modifier(KivoGlass(radius: radius, accent: accent, isRaised: isRaised))
    }
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
