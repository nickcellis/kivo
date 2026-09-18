import SwiftUI

/// Names every file before removing any of them. An uninstaller that only
/// shows a total is asking to be trusted with paths the user never saw.
struct UninstallSheet: View {

    let app: InstalledApp
    @ObservedObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    @State private var plan: UninstallPlan?
    @State private var selected: Set<URL> = []
    @State private var isConfirming = false

    private var selectedBytes: Int64 {

        guard let plan else { return 0 }

        var total: Int64 = 0
        if selected.contains(app.url) { total += app.size }
        for item in plan.leftovers where selected.contains(item.url) {
            total += item.size
        }
        return total
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            header

            Divider().overlay(Color.kivoBorder)

            if let plan {
                list(plan)
            } else {
                loading
            }

            footer
        }
        .frame(width: 480)
        // Opaque on purpose: a sheet floats over the window, so a
        // material here would blur the window's own material and turn
        // the panel grey.
        .background(Color.kivoSurface)
        .task {
            let built = await store.uninstallPlan(for: app)
            plan = built
            // Everything is ticked to begin with, because leaving an app's
            // support files behind is the thing this screen exists to fix.
            selected = Set([app.url] + built.leftovers.map(\.url))
        }
        .confirmationDialog(
            "Remove \(selectedBytes.byteLabel)?",
            isPresented: $isConfirming
        ) {
            Button("Uninstall") {
                if let plan {
                    store.uninstall(plan, items: Array(selected))
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is deleted. Kivo sets these aside and remembers where each came from, so you can put them back.")
        }
    }

    private var subtitle: String {

        guard let id = plan?.bundleID else { return "Reading the bundle" }

        var parts = [id]
        if let version = app.version { parts.append(version) }
        parts.append("opened \(SectionPageConfig.usageLabel(app))")

        return parts.joined(separator: " · ")
    }

    private var header: some View {

        HStack(spacing: 10) {

            Image(nsImage: AppIcons.icon(for: app.url))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {

                Text("Uninstall \(app.name)")
                    .font(KivoFont.pageTitle)
                    .foregroundStyle(Color.kivoText)

                Text(subtitle)
                    .font(KivoFont.mono)
                    .foregroundStyle(Color.kivoDim)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var loading: some View {

        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Looking for the files this app left behind")
                .font(KivoFont.body)
                .foregroundStyle(Color.kivoDim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(_ plan: UninstallPlan) -> some View {

        ScrollView {

            VStack(spacing: 0) {

                row(
                    url: app.url,
                    name: "\(app.name).app",
                    path: app.url.deletingLastPathComponent().path,
                    kind: "Application",
                    size: app.size
                )

                Divider().overlay(Color.kivoBorder)

                if plan.leftovers.isEmpty {

                    Text("This app has not left anything else behind.")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)

                } else {

                    ForEach(plan.leftovers) { item in
                        row(
                            url: item.url,
                            name: item.name,
                            path: item.shortPath,
                            kind: item.kind,
                            size: item.size
                        )
                        Divider().overlay(Color.kivoBorder)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }

    private func row(
        url: URL,
        name: String,
        path: String,
        kind: String,
        size: Int64
    ) -> some View {

        HStack(spacing: 10) {

            Toggle("", isOn: binding(for: url))
                .labelsHidden()
                .toggleStyle(.checkbox)

            Image(nsImage: AppIcons.icon(for: url))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {

                HStack(spacing: 6) {

                    Text(name)
                        .font(KivoFont.body)
                        .foregroundStyle(Color.kivoText)
                        .lineLimit(1)

                    KivoStatusPill(text: kind, tint: .kivoDim)
                }

                Text(path)
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(size.byteLabel)
                .font(KivoFont.mono)
                .foregroundStyle(Color.kivoText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var footer: some View {

        HStack(spacing: 8) {

            VStack(alignment: .leading, spacing: 1) {

                Text(selectedBytes.byteLabel)
                    .font(KivoFont.metricSmall)
                    .foregroundStyle(Color.kivoText)

                Text("\(selected.count) item\(selected.count == 1 ? "" : "s") selected")
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
            }

            Spacer(minLength: 12)

            KivoSecondaryButton(title: "Cancel") { dismiss() }

            KivoButton(title: "Uninstall", icon: "trash") {
                isConfirming = true
            }
            .disabled(selected.isEmpty || plan == nil)
        }
        .padding(14)
    }

    private func binding(for url: URL) -> Binding<Bool> {

        Binding(
            get: { selected.contains(url) },
            set: { isOn in
                if isOn { selected.insert(url) } else { selected.remove(url) }
            }
        )
    }
}
