import SwiftUI

/// What Kivo is holding. Removal and deletion are separate decisions, and
/// this is where the second one is made.
struct QuarantineView: View {

    @ObservedObject var store: ScanStore

    @State private var isPurging = false
    @State private var error: String?

    var body: some View {

        VStack(spacing: KivoMetrics.sectionSpacing) {

            header

            KivoCard(padding: 14) {

                VStack(alignment: .leading, spacing: 10) {

                    KivoCardLabel(
                        text: "Set aside",
                        trailing: store.quarantined.isEmpty ? nil : "Can be put back",
                        trailingTint: .kivoGood,
                        info: """
                            Kivo remembers exactly where each item came \
                            from, so putting it back returns it to the same \
                            place. Deleting it for good cannot be undone.
                            """
                    )

                    let measure = kivoSplitMeasure(store.quarantinedBytes.byteLabel)
                    KivoMetric(value: measure.value, unit: measure.unit)

                    Text(store.quarantined.isEmpty
                        ? "Nothing here yet. Anything Kivo removes waits here until you decide."
                        : holdingLine)
                        .font(KivoFont.body)
                        .foregroundStyle(Color.kivoDim)

                    if let expired = store.expiredOnLaunch, expired.removed > 0 {

                        HStack(spacing: 7) {

                            Text("\(expired.removed) item\(expired.removed == 1 ? "" : "s") reached \(QuarantineRetention.current.shortTitle) and were deleted, freeing \(expired.bytes.byteLabel).")
                                .font(KivoFont.caption)
                                .foregroundStyle(Color.kivoDim)

                            Spacer(minLength: 8)

                            KivoQuietButton(title: "Dismiss") {
                                store.dismissExpiryNotice()
                            }
                        }
                        .padding(.top, 2)
                    }

                    if let error {
                        Text(error)
                            .font(KivoFont.caption)
                            .foregroundStyle(Color.kivoRisk)
                    }

                    if !store.quarantined.isEmpty {

                        HStack(spacing: 7) {

                            KivoDestructiveButton(
                                title: "Delete All for Good",
                                icon: "trash"
                            ) {
                                isPurging = true
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.top, 2)
                    }
                }
            }

            table

            Spacer(minLength: 0)
        }
        .padding(KivoMetrics.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { store.loadQuarantine() }
        .confirmationDialog(
            "Delete everything for good?",
            isPresented: $isPurging
        ) {
            Button("Delete \(store.quarantinedBytes.byteLabel) for good", role: .destructive) {
                store.purgeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These files cannot be recovered afterwards. Put back anything you still want first.")
        }
    }

    private var holdingLine: String {

        let count = store.quarantined.count
        let items = "\(count) item\(count == 1 ? "" : "s") waiting on you"

        guard QuarantineRetention.current != .never else {
            return "\(items). Nothing is deleted automatically."
        }

        return "\(items). Anything left here is deleted after \(QuarantineRetention.current.shortTitle)."
    }

    private var header: some View {

        HStack(alignment: .firstTextBaseline, spacing: 8) {

            Text("Removed Items")
                .font(KivoFont.pageTitle)
                .foregroundStyle(Color.kivoText)

            Text("Nothing here is deleted. Put it back, or delete it for good.")
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)

            Spacer(minLength: 12)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var table: some View {

        KivoCard(padding: 0) {

            VStack(spacing: 0) {

                HStack(spacing: 8) {

                    Text("ITEM")
                        .font(KivoFont.label)
                        .tracking(0.8)
                        .foregroundStyle(Color.kivoDim)

                    Spacer(minLength: 8)

                    Text("SIZE")
                        .font(KivoFont.label)
                        .tracking(0.8)
                        .foregroundStyle(Color.kivoDim)
                        .frame(width: 88, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                Divider().overlay(Color.kivoBorder)

                if store.quarantined.isEmpty {

                    Text("Nothing has been removed yet")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)

                } else {

                    ForEach(store.quarantined) { entry in
                        row(entry)
                        Divider().overlay(Color.kivoBorder)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ entry: QuarantineEntry) -> some View {

        HStack(spacing: 9) {

            if let days = entry.daysLeft() {
                KivoSafetyDot(safety: days <= 3 ? .keep : (days <= 7 ? .check : .safe))
            }

            VStack(alignment: .leading, spacing: 2) {

                HStack(spacing: 6) {

                    Text(entry.name)
                        .font(KivoFont.body)
                        .foregroundStyle(Color.kivoText)
                        .lineLimit(1)

                    KivoStatusPill(text: entry.label, tint: .kivoDim)
                }

                Text(entry.shortPath)
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let days = entry.daysLeft() {
                Text(days == 0 ? "due" : "\(days)d left")
                    .font(KivoFont.mono)
                    .foregroundStyle(days <= 3 ? Color.kivoWarn : Color.kivoDim)
                    .frame(width: 52, alignment: .trailing)
            }

            KivoQuietButton(title: "Put Back") {
                error = store.restore(entry)
            }

            KivoQuietButton(title: "Delete", isDestructive: true) {
                store.purge(entry)
            }

            Text(entry.size.byteLabel)
                .font(KivoFont.mono)
                .foregroundStyle(Color.kivoText)
                .frame(width: 88, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contextMenu {
            // The original path is empty now, so Finder is pointed at the
            // copy Kivo is holding.
            Button("Show in Finder") {
                FileActions.reveal(store.storedURL(for: entry))
            }
            Button("Copy Original Path") {
                FileActions.copyPath(entry.originalURL)
            }
        }
    }
}
