import SwiftUI

/// How the list is ordered. Size descending to begin with, the same order
/// the finder returns, so the biggest thing to reclaim is the first thing
/// read.
enum OrphanSort: Equatable {

    case name(ascending: Bool)
    case kind(ascending: Bool)
    case used(ascending: Bool)
    case size(ascending: Bool)
}

/// Review before removal, and nothing ticked to begin with.
///
/// The Clean sheet arrives with its safe categories already selected,
/// because Kivo knows what those folders are. Here it is guessing which
/// app a folder belonged to, so the default is to take nothing and let the
/// list be read first. Select all is one click away in the header, but it
/// is a click somebody has to make.
struct OrphanSheet: View {

    @ObservedObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<URL> = []
    @State private var sort: OrphanSort = .size(ascending: false)
    @State private var isConfirming = false

    private var rows: [Orphan] {

        switch sort {

        case .name(let ascending):
            return store.orphans.sorted {
                let order = $0.identifier.localizedStandardCompare($1.identifier)
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }

        case .kind(let ascending):
            return store.orphans.sorted {
                // Same kind falls back to size, so the groups read
                // biggest first rather than in whatever order they were
                // found.
                guard $0.kind != $1.kind else { return $0.size > $1.size }
                let order = $0.kind.localizedStandardCompare($1.kind)
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }

        case .used(let ascending):
            return store.orphans.sorted {
                // A folder with no date sorts last either way rather than
                // pretending to be the oldest thing on the list.
                guard let left = $0.modified else { return false }
                guard let right = $1.modified else { return true }
                return ascending ? left < right : left > right
            }

        case .size(let ascending):
            return store.orphans.sorted {
                ascending ? $0.size < $1.size : $0.size > $1.size
            }
        }
    }

    private var selectedBytes: Int64 {
        store.orphans
            .filter { selected.contains($0.url) }
            .reduce(0) { $0 + $1.size }
    }

    private var allSelected: Bool {
        !store.orphans.isEmpty && selected.count == store.orphans.count
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            header

            Divider().overlay(Color.kivoBorder)

            columns

            Divider().overlay(Color.kivoBorder)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { orphan in
                        row(orphan)
                        Divider().overlay(Color.kivoBorder)
                    }
                }
            }
            .frame(maxHeight: 340)

            footer
        }
        .frame(width: 560)
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

    // MARK: Columns

    private var columns: some View {

        HStack(spacing: 10) {

            Toggle("", isOn: Binding(
                get: { allSelected },
                set: { on in
                    selected = on ? Set(store.orphans.map(\.url)) : []
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(store.orphans.isEmpty)
            .help(allSelected ? "Select none" : "Select all")

            column("Name", field: .name(ascending: true))

            Spacer(minLength: 8)

            column("Kind", field: .kind(ascending: true))
                .frame(width: 112, alignment: .leading)

            column("Last used", field: .used(ascending: false), trailing: true)
                .frame(width: 96, alignment: .trailing)

            column("Size", field: .size(ascending: false), trailing: true)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    /// A column heading that sorts, and says which way it is pointing.
    /// Clicking the active one reverses it; clicking another starts that
    /// column at the direction people expect of it, which is A to Z for
    /// text and largest first for a number or a date.
    private func column(
        _ text: String,
        field: OrphanSort,
        trailing: Bool = false
    ) -> some View {

        Button {
            sort = isActive(field) ? reversed(sort) : field
        } label: {

            HStack(spacing: 3) {

                if trailing { Spacer(minLength: 0) }

                Text(text)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isActive(field) ? Color.kivoText : Color.kivoDim)

                if let ascending = direction(field) {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.kivoAccent)
                }

                if !trailing { Spacer(minLength: 0) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kivoPointerCursor()
        .help("Sort by \(text.lowercased())")
    }

    private func isActive(_ field: OrphanSort) -> Bool {

        switch (sort, field) {
        case (.name, .name), (.kind, .kind), (.used, .used), (.size, .size): true
        default: false
        }
    }

    private func direction(_ field: OrphanSort) -> Bool? {

        guard isActive(field) else { return nil }

        return switch sort {
        case .name(let ascending), .kind(let ascending),
             .used(let ascending), .size(let ascending): ascending
        }
    }

    private func reversed(_ current: OrphanSort) -> OrphanSort {

        switch current {
        case .name(let ascending): .name(ascending: !ascending)
        case .kind(let ascending): .kind(ascending: !ascending)
        case .used(let ascending): .used(ascending: !ascending)
        case .size(let ascending): .size(ascending: !ascending)
        }
    }

    // MARK: Rows

    private func row(_ orphan: Orphan) -> some View {

        HStack(spacing: 10) {

            Toggle("", isOn: binding(for: orphan))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 2) {

                Text(orphan.identifier)
                    .font(KivoFont.body)
                    .foregroundStyle(Color.kivoText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(orphan.shortPath)
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            // Fixed so "GROUP CONTAINER" keeps to one line; a pill that
            // wraps makes one row taller than the rest of the list.
            KivoStatusPill(text: orphan.kind, tint: .kivoDim)
                .fixedSize()
                .frame(width: 112, alignment: .leading)

            Text(orphan.modified?.formatted(.relative(presentation: .numeric)) ?? "No record")
                .font(KivoFont.mono)
                .foregroundStyle(Color.kivoDim)
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)

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

                // Nothing is ticked to begin with, so the first thing read
                // here would otherwise be "Zero KB", which looks like a
                // measurement of the list rather than of the selection.
                if selected.isEmpty {

                    Text("Nothing selected")
                        .font(KivoFont.body)
                        .foregroundStyle(Color.kivoText)

                    Text("\(store.orphans.count) item\(store.orphans.count == 1 ? "" : "s") found")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)

                } else {

                    Text(selectedBytes.byteLabel)
                        .font(KivoFont.metricSmall)
                        .foregroundStyle(Color.kivoText)

                    Text("\(selected.count) of \(store.orphans.count) selected")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)
                }
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

    private func binding(for orphan: Orphan) -> Binding<Bool> {

        Binding(
            get: { selected.contains(orphan.url) },
            set: { on in
                if on { selected.insert(orphan.url) } else { selected.remove(orphan.url) }
            }
        )
    }
}
