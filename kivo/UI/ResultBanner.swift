import SwiftUI

/// Says what just happened, and where the files went.
///
/// Without this the only sign a cleanup worked is a number quietly changing
/// somewhere else on the page. It also carries the way back, because the
/// moment someone wants to undo a removal is the moment they've just made it.
struct ResultBanner: View {

    let result: CleanResult
    let mode: RemovalMode
    var onOpenQuarantine: () -> Void = {}
    var onDismiss: () -> Void = {}

    private var headline: String {
        result.removed == 0
            ? "Nothing was removed"
            : "Freed \(result.bytes.byteLabel)"
    }

    private var detail: String {

        var parts: [String] = []

        let noun = result.removed == 1 ? "item" : "items"
        parts.append("\(result.removed) \(noun) moved to \(mode == .trash ? "the Trash" : "Removed Items")")

        if result.failed > 0 {
            let f = result.failed == 1 ? "item was" : "items were"
            parts.append("\(result.failed) \(f) in use and left alone")
        }

        return parts.joined(separator: ". ") + "."
    }

    var body: some View {

        KivoCard(padding: 12, accent: .kivoGood) {

            HStack(spacing: 10) {

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kivoGood)

                VStack(alignment: .leading, spacing: 2) {

                    Text(headline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.kivoText)

                    Text(detail)
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                if mode == .quarantine {
                    KivoSecondaryButton(title: "Put it back") {
                        onOpenQuarantine()
                    }
                } else {
                    Text("Put anything back from the Trash")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.kivoDim)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .kivoPointerCursor()
                .accessibilityLabel("Dismiss")
                .help("Dismiss")
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}
