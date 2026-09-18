import SwiftUI

/// Copies grouped by content, with one kept in each set.
///
/// The files here are identical by hash rather than by guess, so unlike
/// the leftovers sheet it can offer to choose for you. It still doesn't do
/// it silently: "Keep one of each" is a button you press, and which copy
/// survives is visible before anything moves.
struct DuplicateSheet: View {

    @ObservedObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<URL> = []
    @State private var isConfirming = false

    private var selectedBytes: Int64 {

        var total: Int64 = 0

        for set in store.duplicates {
            total += set.size * Int64(set.files.filter { selected.contains($0) }.count)
        }

        return total
    }

    /// True when every set still has at least one copy left unselected.
    /// Selecting a whole set would delete the file entirely, which is not
    /// what a duplicate finder is for.
    private var keepsOneEverywhere: Bool {
        store.duplicates.allSatisfy { set in
            set.files.contains { !selected.contains($0) }
        }
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            header

            Divider().overlay(Color.kivoBorder)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.duplicates) { set in
                        group(set)
                        Divider().overlay(Color.kivoBorder)
                    }
                }
            }
            .frame(maxHeight: 360)

            footer
        }
        .frame(width: 560)
        .background(Color.kivoSurface)
        .confirmationDialog(
            "Remove \(selected.count) cop\(selected.count == 1 ? "y" : "ies")?",
            isPresented: $isConfirming
        ) {
            Button("Remove \(selectedBytes.byteLabel)") {
                store.removeDuplicates(selected)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They go to Removed Items, and every set keeps at least one copy.")
        }
    }

    private var header: some View {

        VStack(alignment: .leading, spacing: 3) {

            Text("Duplicates")
                .font(KivoFont.pageTitle)
                .foregroundStyle(Color.kivoText)

            Text("Files with identical contents. Tick the copies to remove; the ones left unticked stay.")
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    private func group(_ set: DuplicateSet) -> some View {

        VStack(alignment: .leading, spacing: 0) {

            HStack(spacing: 7) {

                Text(set.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kivoText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                KivoStatusPill(text: "\(set.files.count) copies", tint: .kivoWarn)

                Spacer(minLength: 8)

                Text("\(set.size.byteLabel) each")
                    .font(KivoFont.mono)
                    .foregroundStyle(Color.kivoDim)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(set.files, id: \.path) { file in

                HStack(spacing: 9) {

                    Toggle("", isOn: binding(for: file))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .controlSize(.small)

                    Text(file.deletingLastPathComponent().path
                        .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(KivoFont.caption)
                        .foregroundStyle(
                            selected.contains(file) ? Color.kivoDim : Color.kivoText
                        )
                        .strikethrough(selected.contains(file), color: Color.kivoDim)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)
                }
                .padding(.leading, 22)
                .padding(.trailing, 14)
                .padding(.vertical, 2)
                .kivoFileMenu(file)
            }
            .padding(.bottom, 8)
        }
    }

    private var footer: some View {

        HStack(spacing: 8) {

            VStack(alignment: .leading, spacing: 1) {

                Text(selectedBytes.byteLabel)
                    .font(KivoFont.metricSmall)
                    .foregroundStyle(Color.kivoText)

                Text(keepsOneEverywhere
                    ? "\(selected.count) selected"
                    : "a set would lose every copy")
                    .font(KivoFont.caption)
                    .foregroundStyle(keepsOneEverywhere ? Color.kivoDim : Color.kivoRisk)
            }

            Spacer(minLength: 12)

            KivoQuietButton(title: selected.isEmpty ? "Keep one of each" : "Clear") {
                selected = selected.isEmpty
                    ? Set(store.duplicates.flatMap { $0.files.dropFirst() })
                    : []
            }

            KivoSecondaryButton(title: "Cancel") { dismiss() }

            KivoButton(title: "Remove", icon: "tray.full") {
                isConfirming = true
            }
            .disabled(selected.isEmpty || !keepsOneEverywhere)
        }
        .padding(14)
    }

    private func binding(for file: URL) -> Binding<Bool> {

        Binding(
            get: { selected.contains(file) },
            set: { on in
                if on { selected.insert(file) } else { selected.remove(file) }
            }
        )
    }
}
