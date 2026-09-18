import SwiftUI

/// Shows exactly what will be removed before anything is, which is the
/// whole point: a cleaner that acts on a summary figure is asking to be
/// trusted with files the user never saw listed.
struct CleanSheet: View {

    @ObservedObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    /// Caches and logs are on by default because macOS rebuilds them. The
    /// Trash is off: emptying it is permanent, so it has to be chosen.
    /// Only the self-rebuilding folders start ticked. Anything that costs
    /// a re-download is a choice the user makes.
    @State private var selected: Set<CleanCategory.Kind> = Set(
        CleanCategory.Kind.allCases.filter { $0.tier == .safe && $0 != .trash }
    )
    @State private var mode: RemovalMode = .trash
    @State private var isConfirming = false

    /// Which folders the user has opened to look inside.
    @State private var expanded: Set<CleanCategory.Kind> = []

    /// Individual items the user has unticked. Held as exclusions rather
    /// than as a list of things to clear, so an item still being measured
    /// is included by default rather than silently skipped.
    @State private var kept: Set<URL> = []

    @StateObject private var preview = CleanPreview()

    /// Grouped by how free Kivo is with each folder, biggest first inside
    /// each group. Proximity does the explaining: the safe ones sit
    /// together at the top, already ticked.
    private var groups: [(tier: CleanTier, categories: [CleanCategory])] {
        let order: [CleanTier] = [.safe, .rebuildable, .manual]

        return order.compactMap { tier in
            let items = store.categories(tier)
            return items.isEmpty ? nil : (tier, items)
        }
    }

    private var cleanable: [CleanCategory] {
        groups.flatMap(\.categories)
    }

    private var selectedBytes: Int64 {

        cleanable
            .filter { selected.contains($0.kind) }
            .reduce(0) { total, category in
                total + category.size - keptBytes(in: category.kind)
            }
    }

    /// What the unticked children inside a folder come to.
    private func keptBytes(in kind: CleanCategory.Kind) -> Int64 {

        (preview.contents[kind] ?? [])
            .filter { $0.url.map { kept.contains($0.standardizedFileURL) } ?? false }
            .reduce(0) { $0 + $1.size }
    }

    private func keptCount(in kind: CleanCategory.Kind) -> Int {

        (preview.contents[kind] ?? [])
            .filter { $0.url.map { kept.contains($0.standardizedFileURL) } ?? false }
            .count
    }

    private var emptiesTrash: Bool { selected.contains(.trash) }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            header

            Divider().overlay(Color.kivoBorder)

            ScrollView {

                VStack(spacing: 0) {

                    ForEach(groups, id: \.tier.pill) { group in

                        HStack(spacing: 6) {

                            Text(heading(for: group.tier).uppercased())
                                .font(KivoFont.label)
                                .tracking(0.8)
                                .foregroundStyle(Color.kivoDim)

                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 5)

                        ForEach(group.categories) { category in
                            row(for: category)
                            Divider().overlay(Color.kivoBorder)
                        }
                    }
                }
            }
            .frame(maxHeight: 340)

            footer
        }
        .frame(width: 470)
        .background(Color.kivoSurface)
        .onDisappear { preview.cancelAll() }
        .confirmationDialog(
            confirmTitle,
            isPresented: $isConfirming
        ) {
            Button(emptiesTrash ? "Empty the Trash too" : "Move to \(mode.title)") {
                store.clean(selected, mode: mode, emptyTrash: emptiesTrash, keeping: kept)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var header: some View {

        VStack(alignment: .leading, spacing: 3) {

            Text("Free up space")
                .font(KivoFont.pageTitle)
                .foregroundStyle(Color.kivoText)

            Text("Click a folder to see inside, and untick anything you want to keep.")
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)

            Picker("", selection: $mode) {
                ForEach(RemovalMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.top, 6)

            Text(mode.note)
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)
        }
        .padding(14)
    }

    private func row(for category: CleanCategory) -> some View {

        let locked = !category.isRemovable
        let isOpen = expanded.contains(category.kind)

        return VStack(alignment: .leading, spacing: 0) {

            HStack(spacing: 10) {

                Toggle("", isOn: binding(for: category.kind))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(locked)

                // The whole label opens the folder, not just the chevron:
                // a 10pt triangle is a small target for the one action that
                // shows what is about to be removed.
                Button {
                    toggleExpansion(of: category.kind)
                } label: {

                    HStack(spacing: 8) {

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.kivoDim)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .frame(width: 10)

                        VStack(alignment: .leading, spacing: 2) {

                            HStack(spacing: 6) {

                                Text(category.title)
                                    .font(KivoFont.body)
                                    .foregroundStyle(Color.kivoText)

                                if category.kind == .trash {
                                    KivoStatusPill(text: "Cannot undo", tint: .kivoRisk)
                                } else {
                                    KivoStatusPill(
                                        text: category.tier.pill,
                                        tint: SectionPageConfig.tierTint(category.tier)
                                    )
                                }
                            }

                            Text(note(for: category, locked: locked))
                                .font(KivoFont.caption)
                                .foregroundStyle(Color.kivoDim)
                                .fixedSize(horizontal: false, vertical: true)

                            if keptCount(in: category.kind) > 0 {

                                Text("keeping \(keptCount(in: category.kind)) item\(keptCount(in: category.kind) == 1 ? "" : "s") · \(keptBytes(in: category.kind).byteLabel)")
                                    .font(KivoFont.caption)
                                    .foregroundStyle(Color.kivoAccent)
                            }
                        }

                        Spacer(minLength: 8)

                        Text(category.size.byteLabel)
                            .font(KivoFont.mono)
                            .foregroundStyle(locked ? Color.kivoDim : Color.kivoText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .kivoPointerCursor()
                .help(isOpen ? "Hide what's inside" : "See what's inside")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .opacity(locked ? 0.55 : 1)

            if isOpen {
                children(of: category)
            }
        }
    }

    /// What is actually inside, which is what removal would take.
    @ViewBuilder
    private func children(of category: CleanCategory) -> some View {

        let items = preview.contents[category.kind] ?? []
        let shown = items.prefix(12)

        VStack(alignment: .leading, spacing: 0) {

            if items.isEmpty && preview.isLoading(category.kind) {

                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Looking inside")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)
                }
                .padding(.vertical, 6)

            } else if items.isEmpty {

                Text("This folder is empty.")
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
                    .padding(.vertical, 6)

            } else {

                ForEach(shown) { item in

                    let isKept = item.url.map { kept.contains($0.standardizedFileURL) } ?? false

                    HStack(spacing: 7) {

                        Toggle("", isOn: childBinding(for: item))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .disabled(item.url == nil || !category.isRemovable)

                        Text(item.name)
                            .font(KivoFont.caption)
                            .foregroundStyle(isKept ? Color.kivoDim : Color.kivoText)
                            .strikethrough(isKept, color: Color.kivoDim)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        Text(item.size.byteLabel)
                            .font(KivoFont.mono)
                            .foregroundStyle(Color.kivoDim)
                    }
                    .padding(.vertical, 3)
                    .kivoFileMenu(item.url)
                }

                if items.count > shown.count {

                    Text("and \(items.count - shown.count) more")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)
                        .padding(.top, 3)
                }

                if preview.isLoading(category.kind) {

                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("still measuring")
                            .font(KivoFont.caption)
                            .foregroundStyle(Color.kivoDim)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.leading, 52)
        .padding(.trailing, 14)
        .padding(.bottom, 10)
    }

    private func childBinding(for item: DiskEntry) -> Binding<Bool> {

        Binding(
            get: { item.url.map { !kept.contains($0.standardizedFileURL) } ?? false },
            set: { include in
                guard let url = item.url?.standardizedFileURL else { return }
                if include { kept.remove(url) } else { kept.insert(url) }
            }
        )
    }

    private func toggleExpansion(of kind: CleanCategory.Kind) {

        if expanded.contains(kind) {
            expanded.remove(kind)
        } else {
            expanded.insert(kind)
            preview.load(kind)
        }
    }

    private func heading(for tier: CleanTier) -> String {
        switch tier {
        case .safe: "Safe to clear"
        case .rebuildable: "Can go, but you'll download it again"
        case .manual: "Kivo leaves these to you"
        }
    }

    private func note(for category: CleanCategory, locked: Bool) -> String {

        let noun = category.items == 1 ? "item" : "items"
        let count = "\(category.items) \(noun)"

        if let manual = category.kind.manualNote {
            return "\(count). \(manual)"
        }

        if category.kind == .trash {
            return "\(count). Already thrown away, and emptying it cannot be undone."
        }

        return "\(count). \(category.detail.prefix(1).uppercased())\(category.detail.dropFirst())."
    }

    private var footer: some View {

        HStack(spacing: 8) {

            VStack(alignment: .leading, spacing: 1) {

                Text(selectedBytes.byteLabel)
                    .font(KivoFont.metricSmall)
                    .foregroundStyle(Color.kivoText)

                Text("selected")
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
            }

            Spacer(minLength: 12)

            KivoSecondaryButton(title: "Cancel") { dismiss() }

            KivoButton(title: "Free up space", icon: "sparkles") {
                isConfirming = true
            }
            .disabled(selected.isEmpty || selectedBytes == 0)
        }
        .padding(14)
    }

    private var confirmTitle: String {
        emptiesTrash
            ? "Empty the Trash as well?"
            : "Move \(selectedBytes.byteLabel) to \(mode.title)?"
    }

    private var confirmMessage: String {

        if emptiesTrash {
            return "The caches and logs can be recovered. Emptying the Trash cannot be undone."
        }

        return mode == .trash
            ? "You can put anything back from the Trash until you empty it."
            : "Kivo remembers where each one came from, so you can put them back from Removed Items."
    }

    private func binding(for kind: CleanCategory.Kind) -> Binding<Bool> {

        Binding(
            get: { selected.contains(kind) },
            set: { isOn in
                // A folder Kivo won't remove can never be selected,
                // whatever the UI does.
                guard kind.tier != .manual else { return }
                if isOn { selected.insert(kind) } else { selected.remove(kind) }
            }
        )
    }
}
