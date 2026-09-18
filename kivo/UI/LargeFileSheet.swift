import SwiftUI

/// The only sheet in Kivo that lists nothing but the user's own documents.
///
/// Caches rebuild, leftovers belong to apps that are gone, duplicates keep
/// a copy. A 6 GB video has none of those safety nets, so nothing is
/// selected, the button says what it does, and everything still goes to
/// quarantine rather than out.
struct LargeFileSheet: View {

    @ObservedObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<URL> = []
    @State private var isConfirming = false

    private var selectedBytes: Int64 {
        store.largeFiles
            .filter { selected.contains($0.url) }
            .reduce(0) { $0 + $1.size }
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            header

            Divider().overlay(Color.kivoBorder)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.largeFiles) { file in
                        row(file)
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
            "Set aside \(selectedBytes.byteLabel)?",
            isPresented: $isConfirming
        ) {
            Button("Remove \(selected.count) file\(selected.count == 1 ? "" : "s")") {
                store.removeLargeFiles(selected)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These are your own files. They go to Removed Items, where you can put them back.")
        }
    }

    private var header: some View {

        VStack(alignment: .leading, spacing: 3) {

            Text("Large files")
                .font(KivoFont.pageTitle)
                .foregroundStyle(Color.kivoText)

            Text("Your documents, not debris. Open anything you're unsure about before ticking it.")
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    private func row(_ file: LargeFile) -> some View {

        HStack(spacing: 9) {

            Toggle("", isOn: binding(for: file.url))
                .labelsHidden()
                .toggleStyle(.checkbox)

            Image(nsImage: AppIcons.icon(for: file.url))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {

                Text(file.name)
                    .font(KivoFont.body)
                    .foregroundStyle(Color.kivoText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.url.deletingLastPathComponent().path
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(file.size.byteLabel)
                .font(KivoFont.mono)
                .foregroundStyle(Color.kivoText)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .kivoFileMenu(file.url)
    }

    private var footer: some View {

        HStack(spacing: 8) {

            VStack(alignment: .leading, spacing: 1) {

                Text(selectedBytes.byteLabel)
                    .font(KivoFont.metricSmall)
                    .foregroundStyle(Color.kivoText)

                Text("\(selected.count) of \(store.largeFiles.count) selected")
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
            }

            Spacer(minLength: 12)

            KivoSecondaryButton(title: "Cancel") { dismiss() }

            KivoButton(title: "Remove", icon: "tray.full") {
                isConfirming = true
            }
            .disabled(selected.isEmpty)
        }
        .padding(14)
    }

    private func binding(for url: URL) -> Binding<Bool> {

        Binding(
            get: { selected.contains(url) },
            set: { on in
                if on { selected.insert(url) } else { selected.remove(url) }
            }
        )
    }
}
