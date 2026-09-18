import SwiftUI

/// Flat panel with a hairline edge. On navy the edge is a light hairline,
/// on paper a dark one — same role, so cards read identically in both.
struct KivoCard<Content: View>: View {

    var padding: CGFloat = KivoMetrics.cardPadding
    var isRaised: Bool = false
    var accent: Color?

    /// Stretches the card to the tallest in its row. Without it a row of
    /// cards with different content lengths ends in ragged bottom edges.
    var fillsHeight: Bool = false

    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: KivoMetrics.cardRadius,
            style: .continuous
        )
    }

    private var border: Color {
        if isRaised { return .kivoAccent.opacity(0.6) }
        if let accent { return accent.opacity(0.35) }
        return .kivoBorder
    }

    var body: some View {

        content
            .padding(padding)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .kivoGlass(
                accent: isRaised ? .kivoAccent : accent,
                isRaised: isRaised
            )
            .animation(.easeOut(duration: 0.13), value: isRaised)
    }
}

