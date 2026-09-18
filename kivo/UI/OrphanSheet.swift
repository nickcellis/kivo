import SwiftUI

/// Review before removal, and nothing ticked to begin with.
///
/// The Clean sheet arrives with its safe categories already selected,
/// because Kivo knows what those folders are. Here it is guessing which
/// app a folder belonged to, so the default is to take nothing and let the
/// list be read first.
struct OrphanSheet: View {

    @ObservedObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<URL> = []
    @State private var isConfirming = false

    private var selectedBytes: Int64 {
        store.orphans
            .filter { selected.contains($0.url) }
            .reduce(0) { $0 + $1.size }
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            header

            Divider().overlay(Color.kivoBorder)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.orphans) { orphan in
                        row(orphan)
                        Divider().overlay(Color.kivoBorder)
                    }
                }
            }
            .frame(maxHeight: 340)

            footer
        }
        .frame(width: 520)
        .background(Color.kivoSurface)
        .confirmationDialog(
            "Set aside \(selectedBytes.byteLabel)?",
            isPresented: $isConfirming
        ) {
            Button("Remove \(selected.count) item\(selected.count == 1 ? "" : "s")") {
                store.removeOrphans(selected)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These go to Removed Items, where you can put any of them back if an app turns out to still need them.")
        }
    }

    private var header: some View {

        VStack(alignment: .leading, spacing: 3) {

            Text("Leftovers")
                .font(KivoFont.pageTitle)
                .foregroundStyle(Color.kivoText)

            Text("Support files whose app Kivo can't find. Check anything you recognise before removing it.")
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    private func row(_ orphan: Orphan) -> some View {

        HStack(spacing: 10) {

            Toggle("", isOn: binding(for: orphan))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 2) {

                HStack(spacing: 6) {

                    Text(orphan.identifier)
                        .font(KivoFont.body)
                        .foregroundStyle(Color.kivoText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    KivoStatusPill(text: orphan.kind, tint: .kivoDim)
                }

                Text(orphan.shortPath)
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let modified = orphan.modified {
                Text(modified.formatted(.relative(presentation: .numeric)))
                    .font(KivoFont.mono)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)
            }

            Text(orphan.size.byteLabel)
                .font(KivoFont.mono)
                .foregroundStyle(Color.kivoText)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .kivoFileMenu(orphan.url)
    }

    private var footer: some View {

        HStack(spacing: 8) {

            VStack(alignment: .leading, spacing: 1) {

                Text(selectedBytes.byteLabel)
                    .font(KivoFont.metricSmall)
                    .foregroundStyle(Color.kivoText)

                Text("\(selected.count) of \(store.orphans.count) selected")
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
            }

            Spacer(minLength: 12)

            KivoQuietButton(title: selected.isEmpty ? "Select all" : "Select none") {
                selected = selected.isEmpty
                    ? Set(store.orphans.map(\.url))
                    : []
            }

            KivoSecondaryButton(title: "Cancel") { dismiss() }

            KivoButton(title: "Remove", icon: "tray.full") {
                isConfirming = true
            }
            .disabled(selected.isEmpty)
        }
        .padding(14)
    }

    private func binding(for orphan: Orphan) -> Binding<Bool> {

        Binding(
            get: { selected.contains(orphan.url) },
            set: { on in
                if on { selected.insert(orphan.url) } else { selected.remove(orphan.url) }
            }
        )
    }
}
