import Foundation

/// Lists what is actually inside a category before anything is removed.
///
/// The cleaner moves a folder's immediate children, so those are exactly
/// what this lists: the preview and the action see the same set of items,
/// rather than the preview being an approximation of it.
@MainActor
final class CleanPreview: ObservableObject {

    @Published private(set) var contents: [CleanCategory.Kind: [DiskEntry]] = [:]
    @Published private(set) var loading: Set<CleanCategory.Kind> = []

    private var tasks: [CleanCategory.Kind: Task<Void, Never>] = [:]

    /// Sizing children means a walk each, so results arrive as they land
    /// and the list grows rather than appearing all at once.
    func load(_ kind: CleanCategory.Kind, home: URL? = nil) {

        guard contents[kind] == nil, !loading.contains(kind) else { return }

        loading.insert(kind)

        let folder = SystemCleaner.root(for: kind, home: home)

        tasks[kind] = Task { [weak self] in

            guard let self else { return }

            let children = await Task.detached(priority: .userInitiated) {
                (try? FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                )) ?? []
            }.value

            var measured: [DiskEntry] = []

            for child in children {

                if Task.isCancelled { return }

                let entry = await Task.detached(priority: .userInitiated) { () -> DiskEntry in

                    let values = try? child.resourceValues(
                        forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey]
                    )

                    let isDirectory = values?.isDirectory ?? false

                    let size: Int64 = isDirectory
                        ? SystemScanner.directoryStats(at: child) { Task.isCancelled }.size
                        : Int64(values?.totalFileAllocatedSize ?? 0)

                    return DiskEntry(
                        url: child,
                        name: child.lastPathComponent,
                        size: size,
                        isDirectory: isDirectory
                    )
                }.value

                measured.append(entry)
                self.contents[kind] = measured.sorted { $0.size > $1.size }
            }

            self.contents[kind] = measured.sorted { $0.size > $1.size }
            self.loading.remove(kind)
        }
    }

    func isLoading(_ kind: CleanCategory.Kind) -> Bool {
        loading.contains(kind)
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        loading = []
    }
}
