import SwiftUI

// MARK: - Status

enum KivoStatus {

    case good
    case attention
    case risk

    var tint: Color {
        switch self {
        case .good: .kivoGood
        case .attention: .kivoWarn
        case .risk: .kivoRisk
        }
    }

    var glyph: String {
        switch self {
        case .good: "checkmark"
        case .attention: "exclamationmark"
        case .risk: "xmark"
        }
    }

    var label: String {
        switch self {
        case .good: "All clear"
        case .attention: "Needs attention"
        case .risk: "At risk"
        }
    }

    /// For the sidebar footer, where the full wording was the widest thing
    /// in the column and set its minimum width on its own. The hero keeps
    /// the long form, which is where the sentence has room to be a
    /// sentence.
    var shortLabel: String {
        switch self {
        case .good: "Clear"
        case .attention: "Attention"
        case .risk: "At risk"
        }
    }
}

// MARK: - Card label

/// Uppercase monospace label with a status dot, the thing that heads every
/// card. The dot carries the state so the label doesn't have to say it.
struct KivoCardLabel: View {

    let text: String
    var trailing: String?
    var trailingTint: Color = .kivoDim

    /// When set, an i button sits beside the label explaining where the
    /// figure comes from. A number nobody can interrogate is just decoration.
    var info: String?

    var body: some View {

        HStack(spacing: 6) {

            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.kivoDim)

            if let info {
                KivoInfoButton(text: info)
            }

            Spacer(minLength: 8)

            if let trailing {
                KivoStatusPill(text: trailing, tint: trailingTint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Info

/// Small i that opens a popover. Every figure in Kivo comes from a
/// particular folder measured a particular way, and the difference between
/// "free" and "available" is the sort of thing a tooltip has to carry.
struct KivoInfoButton: View {

    let text: String

    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {

        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHovering ? Color.kivoText : Color.kivoDim.opacity(0.7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {

            Text(text)
                .font(KivoFont.body)
                .foregroundStyle(Color.kivoText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(14)
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .kivoPointerCursor()
        .accessibilityLabel("About this figure")
        .help("About this figure")
    }
}

// MARK: - Pill

struct KivoStatusPill: View {

    let text: String

    /// Neutral unless something is actually wrong. Six green pills on one
    /// screen is the same as none: the eye stops reading them.
    var tint: Color = .kivoDim

    var body: some View {

        Text(text.uppercased())
            .font(KivoFont.pill)
            .tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(tint.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel(text)
    }
}

// MARK: - Metric

/// A big monospace figure with a small unit beside it. Splitting the unit
/// off keeps the number the thing you read.
struct KivoMetric: View {

    let value: String
    var unit: String?
    var small: Bool = false

    var body: some View {

        HStack(alignment: .firstTextBaseline, spacing: 4) {

            Text(value)
                .font(small ? KivoFont.metricSmall : KivoFont.metric)
                .foregroundStyle(Color.kivoText)

            if let unit {
                Text(unit)
                    .font(KivoFont.unit)
                    .foregroundStyle(Color.kivoDim)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }
}

/// Splits "318.09 GB" into figure and unit so the two can be typeset apart.
func kivoSplitMeasure(_ text: String) -> (value: String, unit: String?) {

    let parts = text.split(separator: " ", maxSplits: 1)

    guard parts.count == 2 else { return (text, nil) }
    return (String(parts[0]), String(parts[1]))
}

// MARK: - Bars

struct KivoProgressBar: View {

    let fraction: Double

    /// Neutral by default. A capacity bar is a reading, not an alarm.
    var tint: Color = .kivoDim
    var height: CGFloat = 4

    var body: some View {

        GeometryReader { proxy in

            ZStack(alignment: .leading) {

                Capsule().fill(Color.kivoFill)

                Capsule()
                    .fill(tint)
                    .frame(
                        width: max(
                            height,
                            proxy.size.width * min(max(fraction, 0), 1)
                        )
                    )
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Proportional segments of one bar — how a disk's composition reads in one
/// line without a pie chart.
struct KivoSegmentBar: View {

    struct Segment: Identifiable {
        let id = UUID()
        let fraction: Double
        let tint: Color
    }

    let segments: [Segment]
    var height: CGFloat = 6

    var body: some View {

        GeometryReader { proxy in

            HStack(spacing: 1.5) {

                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.tint)
                        .frame(
                            width: max(
                                2,
                                proxy.size.width * min(max(segment.fraction, 0), 1)
                            )
                        )
                }

                Rectangle().fill(Color.kivoFill)
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#Preview {

    VStack(alignment: .leading, spacing: 14) {

        KivoCardLabel(text: "Disk", trailing: "64% full", trailingTint: .kivoWarn)
        KivoMetric(value: "176.24", unit: "GB free")
        KivoProgressBar(fraction: 0.64, tint: .kivoWarn)
        KivoSegmentBar(segments: [
            .init(fraction: 0.45, tint: .kivoAccent),
            .init(fraction: 0.12, tint: .kivoWarn),
            .init(fraction: 0.07, tint: .kivoGood)
        ])
    }
    .padding(20)
    .frame(width: 320)
    .background(Color.kivoBackground)
}
