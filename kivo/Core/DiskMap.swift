import Foundation
import SwiftUI

/// One box on the map: a file, a folder, or the lump everything too small
/// to draw gets folded into.
struct DiskEntry: Identifiable, Equatable {

    let url: URL?
    let name: String
    let size: Int64
    let isDirectory: Bool

    /// Set on the aggregate row, which can't be opened or revealed.
    var aggregatedCount: Int?

    var id: String { url?.path ?? "other-\(name)" }
    var isAggregate: Bool { aggregatedCount != nil }

    /// Stable per name, so a folder keeps its colour between redraws and
    /// between visits. Colour carries no meaning here beyond telling one
    /// box from the next.
    var tint: Color {

        // Blues and teals around the accent, with two warm tones held at
        // the same lightness so neighbouring boxes stay distinguishable
        // without any of them shouting.
        let palette: [Color] = [
            Color(red: 0.204, green: 0.400, blue: 0.663),
            Color(red: 0.278, green: 0.522, blue: 0.671),
            Color(red: 0.239, green: 0.565, blue: 0.561),
            Color(red: 0.353, green: 0.451, blue: 0.639),
            Color(red: 0.310, green: 0.612, blue: 0.639),
            Color(red: 0.443, green: 0.498, blue: 0.588),
            Color(red: 0.600, green: 0.463, blue: 0.435),
            Color(red: 0.549, green: 0.525, blue: 0.376)
        ]

        guard !isAggregate else { return Color.kivoDim.opacity(0.45) }

        let hash = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

/// Walks one level of a directory at a time.
///
/// Sizing every child means a full walk per child, so this is the slowest
/// thing in Kivo. It reports each child as it lands rather than at the end,
/// which is why the map fills in rather than appearing all at once.
@MainActor
final class DiskMapStore: ObservableObject {

    /// Breadcrumb, root first.
    @Published private(set) var trail: [URL]
    @Published private(set) var entries: [DiskEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0

    /// Anything under this share of the parent is folded into one box.
    /// Below about half a percent a rectangle is too small to label or
    /// click, and a hundred of them turn the map into noise.
    private let minimumShare = 0.005

    private var task: Task<Void, Never>?

    init(root: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        trail = [root]
    }

    var current: URL { trail.last ?? URL(fileURLWithPath: NSHomeDirectory()) }
    var canGoUp: Bool { trail.count > 1 }
    var total: Int64 { entries.reduce(0) { $0 + $1.size } }

    // MARK: Navigation

    func open(_ entry: DiskEntry) {
        guard entry.isDirectory, let url = entry.url else { return }
        trail.append(url)
        load()
    }

    func goUp() {
        guard canGoUp else { return }
        trail.removeLast()
        load()
    }

    /// Jumps straight to a crumb rather than stepping back one at a time.
    func go(to index: Int) {
        guard trail.indices.contains(index), index < trail.count - 1 else { return }
        trail = Array(trail.prefix(index + 1))
        load()
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    // MARK: Loading

    func load() {

        task?.cancel()
        entries = []
        progress = 0
        isLoading = true

        let folder = current

        task = Task { [weak self] in

            guard let self else { return }

            let children = await Self.contents(of: folder)
            var measured: [DiskEntry] = []

            for (index, child) in children.enumerated() {

                if Task.isCancelled { return }

                let entry = await Self.measure(child)
                measured.append(entry)

                await self.update(
                    entries: Self.fold(measured, below: self.minimumShare),
                    progress: Double(index + 1) / Double(max(children.count, 1))
                )
            }

            await self.finish(Self.fold(measured, below: self.minimumShare))
        }
    }

    private static func contents(of folder: URL) async -> [URL] {

        await Task.detached(priority: .userInitiated) {
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )) ?? []
        }.value
    }

    private static func measure(_ url: URL) async -> DiskEntry {

        await Task.detached(priority: .userInitiated) {

            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey]
            )

            let isDirectory = values?.isDirectory ?? false

            let size: Int64 = isDirectory
                ? SystemScanner.directoryStats(at: url) { Task.isCancelled }.size
                : Int64(values?.totalFileAllocatedSize ?? 0)

            return DiskEntry(
                url: url,
                name: url.lastPathComponent,
                size: size,
                isDirectory: isDirectory
            )
        }.value
    }

    /// Sorts largest first and folds the tail into one box.
    private static func fold(_ entries: [DiskEntry], below share: Double) -> [DiskEntry] {

        let sorted = entries.sorted { $0.size > $1.size }
        let total = sorted.reduce(0) { $0 + $1.size }

        guard total > 0 else { return sorted }

        let cutoff = Double(total) * share
        let kept = sorted.filter { Double($0.size) >= cutoff }
        let rest = sorted.filter { Double($0.size) < cutoff }

        guard rest.count > 1 else { return sorted }

        let restSize = rest.reduce(0) { $0 + $1.size }

        return kept + [
            DiskEntry(
                url: nil,
                name: "\(rest.count) smaller items",
                size: restSize,
                isDirectory: false,
                aggregatedCount: rest.count
            )
        ]
    }

    private func update(entries: [DiskEntry], progress: Double) {
        self.entries = entries
        self.progress = progress
    }

    private func finish(_ entries: [DiskEntry]) {
        self.entries = entries
        progress = 1
        isLoading = false
    }
}
