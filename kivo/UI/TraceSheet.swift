import SwiftUI

/// What turned up after an uninstall, offered for review.
///
/// It appears on its own, which nothing else in Kivo does, and the reason
/// is that this list has a moment: it is the answer to something the user
/// just did, and a minute later they are somewhere else and will never
/// look for it. Nothing is ticked, and dismissing it removes nothing —
/// the files stay where they are and the next leftovers scan will find
/// them again.
struct TraceSheet: View {

    let trace: UninstallTrace
    @ObservedObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<URL> = []
    @State private var isConfirming = false

    private var selectedBytes: Int64 {
        trace.items
            .filter { selected.contains($0.url) }
            .reduce(0) { $0 + $1.size }
    }

    private var allSelected: Bool {
        !trace.items.isEmpty && selected.count == trace.items.count
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            header

            Divider().overlay(Color.kivoBorder)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(trace.items) { item in
                        row(item)
                        Divider().overlay(Color.kivoBorder)
                    }
                }
            }
            .frame(maxHeight: 300)

            footer
        }
        .frame(width: 560)
        .background(Color.kivoSurface)
        .confirmationDialog(
            "Set aside \(selectedBytes.byteLabel)?",
            isPresented: $isConfirming
        ) {
            Button("Remove \(selected.count) item\(selected.count == 1 ? "" : "s")") {
                store.removeTraced(selected)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These go to Removed Items, where you can put any of them back.")
        }
    }

    private var header: some View {

        VStack(alignment: .leading, spacing: 4) {

            HStack(spacing: 8) {

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kivoAccent)

                Text("\(trace.app) left more behind")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.kivoText)
            }

            Text("After removing \(trace.app), Kivo looked again and found \(trace.items.count) file\(trace.items.count == 1 ? "" : "s") from \(trace.vendor) that no installed app answers to — \(trace.bytes.byteLabel) in total. Helpers and extensions carry their own names, so they survive the uninstall itself.")
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    private func row(_ item: Orphan) -> some View {

        HStack(spacing: 10) {

            Toggle("", isOn: binding(for: item))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 2) {

                Text(item.identifier)
                    .font(KivoFont.body)
                    .foregroundStyle(Color.kivoText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.shortPath)
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            KivoStatusPill(text: item.kind, tint: .kivoDim)
                .fixedSize()
                .frame(width: 112, alignment: .leading)

            Text(item.size.byteLabel)
                .font(KivoFont.mono)
                .foregroundStyle(Color.kivoText)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .kivoFileMenu(item.url)
    }

    private var footer: some View {

        HStack(spacing: 8) {

            KivoQuietButton(title: allSelected ? "Select none" : "Select all") {
                selected = allSelected ? [] : Set(trace.items.map(\.url))
            }

            Spacer(minLength: 12)

            // Not "Cancel": nothing is pending, so there is nothing to
            // cancel. Leaving them is a choice, and the button says so.
            KivoSecondaryButton(title: "Leave Them") { dismiss() }

            KivoButton(title: "Remove", icon: "tray.full") {
                isConfirming = true
            }
            .disabled(selected.isEmpty)
        }
        .padding(14)
    }

    private func binding(for item: Orphan) -> Binding<Bool> {

        Binding(
            get: { selected.contains(item.url) },
            set: { on in
                if on { selected.insert(item.url) } else { selected.remove(item.url) }
            }
        )
    }
}
