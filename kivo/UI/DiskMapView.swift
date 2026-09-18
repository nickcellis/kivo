import SwiftUI

/// A treemap of one folder at a time: every box is a child, its area is its
/// share of the space, and clicking a folder goes into it.
///
/// A table can tell you the ten biggest things. A map tells you the shape
/// of the problem, which is usually one folder nobody expected.
struct DiskMapView: View {

    @StateObject private var store = DiskMapStore()
    @State private var hovered: DiskEntry?

    var body: some View {

        VStack(spacing: KivoMetrics.sectionSpacing) {

            header
            breadcrumb
            map
        }
        .padding(KivoMetrics.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { if store.entries.isEmpty { store.load() } }
    }

    // MARK: Header

    private var header: some View {

        HStack(alignment: .firstTextBaseline, spacing: 8) {

            Text("Disk Map")
                .font(KivoFont.pageTitle)
                .foregroundStyle(Color.kivoText)

            Text("Every box is sized by what it holds. Click a folder to go in.")
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)
                .lineLimit(1)

            Spacer(minLength: 12)

            if store.isLoading {

                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("\(Int(store.progress * 100))%")
                        .font(KivoFont.mono)
                        .foregroundStyle(Color.kivoDim)
                }

            } else {

                Text(store.total.byteLabel)
                    .font(KivoFont.mono)
                    .foregroundStyle(Color.kivoText)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Breadcrumb

    private var breadcrumb: some View {

        HStack(spacing: 5) {

            KivoQuietButton(title: "Up", icon: "arrow.up") {
                store.goUp()
            }
            .disabled(!store.canGoUp)
            .opacity(store.canGoUp ? 1 : 0.4)

            Divider().frame(height: 14).overlay(Color.kivoBorder)

            ForEach(Array(store.trail.enumerated()), id: \.element) { index, url in

                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.kivoDim.opacity(0.6))
                }

                Button {
                    store.go(to: index)
                } label: {
                    Text(index == 0 ? "Home" : url.lastPathComponent)
                        .font(KivoFont.caption)
                        .foregroundStyle(
                            index == store.trail.count - 1 ? Color.kivoText : Color.kivoDim
                        )
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .kivoPointerCursor()
                .disabled(index == store.trail.count - 1)
            }

            Spacer(minLength: 8)

            if let hovered {

                Text("\(hovered.name) · \(hovered.size.byteLabel)")
                    .font(KivoFont.mono)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Map

    private var map: some View {

        KivoCard(padding: 6) {

            GeometryReader { proxy in

                let bounds = CGRect(origin: .zero, size: proxy.size)
                let values = store.entries.map { Double($0.size) }
                let rects = TreemapLayout.rects(for: values, in: bounds)

                ZStack(alignment: .topLeading) {

                    if store.entries.isEmpty {

                        Text(store.isLoading ? "Measuring…" : "Nothing to show here")
                            .font(KivoFont.caption)
                            .foregroundStyle(Color.kivoDim)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                    } else {

                        ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in

                            if index < rects.count {
                                box(entry, in: rects[index])
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func box(_ entry: DiskEntry, in rect: CGRect) -> some View {

        let isHovered = hovered == entry
        // Below this a label is unreadable, so the box carries its name in
        // the hover line and the tooltip instead of clipping text into it.
        let showsLabel = rect.width > 64 && rect.height > 26

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(entry.tint.opacity(isHovered ? 0.95 : 0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {

                if showsLabel {

                    VStack(alignment: .leading, spacing: 1) {

                        Text(entry.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(entry.size.byteLabel)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(5)
                }
            }
            .frame(width: max(rect.width - 1.5, 0), height: max(rect.height - 1.5, 0))
            .offset(x: rect.minX, y: rect.minY)
            .onHover { hovered = $0 ? entry : nil }
            .onTapGesture { store.open(entry) }
            .kivoFileMenu(entry.url)
            .help("\(entry.name) · \(entry.size.byteLabel)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.name), \(entry.size.byteLabel)")
            .accessibilityAddTraits(entry.isDirectory ? .isButton : [])
    }
}
