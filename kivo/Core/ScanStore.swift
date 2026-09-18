import Foundation
import SwiftUI

/// What a scan covers. Each page asks for the part it shows, so pressing
/// Scan on Applications reads /Applications instead of also walking the
/// whole home folder for files over 1 GB.
enum ScanScope: String, CaseIterable, Hashable {

    case disk
    case cleanable
    case applications
    case largeFiles
    case orphans
    case duplicates

    static let everything = Set(ScanScope.allCases)

    var label: String {
        switch self {
        case .disk: "Reading the disk"
        case .cleanable: "Measuring caches and logs"
        case .applications: "Checking applications"
        case .largeFiles: "Looking for large files"
        case .orphans: "Checking for leftovers"
        case .duplicates: "Comparing files for copies"
        }
    }

    /// Roughly how long each leg takes, so the bar tracks time rather than
    /// step count. The home folder walk is by far the longest.
    var weight: Double {
        switch self {
        case .disk: 0.02
        case .cleanable: 0.34
        case .applications: 0.24
        case .largeFiles: 0.40
        case .orphans: 0.22
        case .duplicates: 0.30
        }
    }
}

/// One thing a scan does, named so the user can watch it happen.
struct ScanStep: Identifiable, Equatable {

    enum State: Equatable {
        case pending
        case running
        case done
    }

    let id: String
    let title: String
    let icon: String
    let weight: Double
    var state: State = .pending
}

/// The unit of work behind a step. Keeping the two together is what stops
/// the label saying "checking applications" while something else runs.
private enum ScanTask: Equatable {

    case disk
    case category(CleanCategory.Kind)
    case applications
    case largeFiles
    case orphans
    case duplicates

    var id: String {
        switch self {
        case .disk: "disk"
        case .category(let kind): "category.\(kind.rawValue)"
        case .applications: "applications"
        case .largeFiles: "largeFiles"
        case .orphans: "orphans"
        case .duplicates: "duplicates"
        }
    }

    var title: String {
        switch self {
        case .disk: "Reading the disk"
        case .category(let kind): "Measuring \(kind.title.lowercased())"
        case .applications: "Checking applications"
        case .largeFiles: "Looking for large files"
        case .orphans: "Checking for leftovers"
        case .duplicates: "Comparing files for copies"
        }
    }

    var icon: String {
        switch self {
        case .disk: "internaldrive"
        case .category(let kind): kind.icon
        case .applications: "square.stack.3d.up"
        case .largeFiles: "doc"
        case .orphans: "shippingbox"
        case .duplicates: "doc.on.doc"
        }
    }

    /// Roughly how long each takes, so the bar tracks time rather than
    /// counting steps. The home folder walk dwarfs the rest.
    var weight: Double {
        switch self {
        case .disk: 0.02
        case .category(let kind):
            switch kind {
            case .caches, .pnpmStore, .coreSimulator: 0.12
            default: 0.04
            }
        case .applications: 0.24
        case .largeFiles: 0.40
        case .orphans: 0.22
        case .duplicates: 0.30
        }
    }
}

/// Everything the UI knows about this Mac. One store, read by every page,
/// so two screens can't disagree about what's on the disk.
@MainActor
final class ScanStore: ObservableObject {

    enum Phase: Equatable {

        case idle
        case scanning(progress: Double, label: String)
        case finished

        var isScanning: Bool {
            if case .scanning = self { return true }
            return false
        }

        var progress: Double {
            if case .scanning(let value, _) = self { return value }
            return 0
        }
    }

    @Published private(set) var phase: Phase = .idle

    /// What this scan is doing, and what it has already done.
    @Published private(set) var steps: [ScanStep] = []
    @Published private(set) var volume: VolumeInfo?
    @Published private(set) var categories: [CleanCategory] = []
    @Published private(set) var largeFiles: [LargeFile] = []
    @Published private(set) var apps: [InstalledApp] = []

    /// Support files whose app is gone. Never acted on without review.
    @Published private(set) var orphans: [Orphan] = []

    /// Files with identical contents, grouped.
    @Published private(set) var duplicates: [DuplicateSet] = []

    /// Which parts have real figures behind them. A page that hasn't been
    /// scanned shows a dash rather than borrowing another page's freshness.
    @Published private(set) var measured: Set<ScanScope> = []
    @Published private(set) var lastScan: Date?

    /// Cleanup state. Kept beside the scan state because a cleanup has to
    /// re-measure when it finishes: the figures on screen describe files
    /// that are now in the Trash.
    @Published private(set) var isCleaning = false
    @Published private(set) var cleanProgress: Double = 0
    @Published private(set) var lastClean: CleanResult?
    @Published private(set) var lastCleanAt: Date?
    @Published private(set) var lastCleanMode: RemovalMode = .trash

    /// Cleared when the user dismisses the confirmation, so the banner
    /// reports one action rather than sitting there for the session.
    @Published var showsCleanResult = false

    /// What Kivo is holding rather than deleting.
    @Published private(set) var quarantined: [QuarantineEntry] = []

    private let quarantine = Quarantine.shared
    private let archive = KivoArchive.shared

    /// Every cleanup Kivo has run, oldest first, capped by the archive.
    @Published private(set) var cleanHistory: [CleanEvent] = []

    /// How many scans have completed, across launches.
    @Published private(set) var scanCount = 0

    /// Re-read on launch and after a scan, since the only way to know is
    /// to try. Granting it requires relaunching Kivo, so this does not
    /// need to be live.
    @Published private(set) var hasFullDisk = DiskAccess.hasFullDisk

    private var task: Task<Void, Never>?

    var currentStep: ScanStep? { steps.first { $0.state == .running } }
    var stepsDone: Int { steps.filter { $0.state == .done }.count }

    #if DEBUG
    /// Fills the store with a fictional Mac, for the README's pictures.
    /// See DemoData: it exists so the screenshots aren't of somebody's
    /// real disk. Debug only.
    func loadDemo() {

        volume = DemoData.volume
        categories = DemoData.categories
        apps = DemoData.apps
        orphans = DemoData.orphans
        largeFiles = DemoData.largeFiles
        duplicates = DemoData.duplicates
        quarantined = DemoData.quarantined
        measured = [.disk, .cleanable, .applications, .largeFiles, .orphans, .duplicates]
        lastScan = Calendar.current.date(byAdding: .minute, value: -8, to: .now)
        scanCount = 12
        phase = .finished
    }
    #endif

    func has(_ scope: ScanScope) -> Bool { measured.contains(scope) }

    func has(_ scopes: Set<ScanScope>) -> Bool {
        !scopes.isEmpty && scopes.isSubset(of: measured)
    }

    var hasScanned: Bool { !measured.isEmpty }

    // MARK: Derived totals

    /// Only the folders that rebuild themselves. Anything that costs a
    /// re-download, and anything that belongs to the user, is reported
    /// separately rather than folded into the headline figure.
    var cleanableBytes: Int64 {
        categories.filter(\.isSafe).reduce(0) { $0 + $1.size }
    }

    /// Removable, but you pay to get it back.
    var rebuildableBytes: Int64 {
        categories.filter { $0.tier == .rebuildable }.reduce(0) { $0 + $1.size }
    }

    /// Measured, never removed by Kivo.
    var manualBytes: Int64 {
        categories.filter { $0.tier == .manual }.reduce(0) { $0 + $1.size }
    }

    func categories(_ tier: CleanTier) -> [CleanCategory] {
        categories.filter { $0.tier == tier }.sorted { $0.size > $1.size }
    }

    var largeFileBytes: Int64 {
        largeFiles.reduce(0) { $0 + $1.size }
    }

    var appsBytes: Int64 {
        apps.reduce(0) { $0 + $1.size }
    }

    var orphanBytes: Int64 {
        orphans.reduce(0) { $0 + $1.size }
    }

    /// What keeping every copy costs, which is the total minus one of each.
    var duplicateBytes: Int64 {
        duplicates.reduce(0) { $0 + $1.reclaimable }
    }

    var duplicateFileCount: Int {
        duplicates.reduce(0) { $0 + $1.files.count }
    }

    /// Apps nobody has opened in months, largest first. The uninstaller's
    /// missing signal: size says which app is big, this says which one you
    /// have stopped using.
    var unusedApps: [InstalledApp] {
        apps.filter { $0.isUnused() }.sorted { $0.size > $1.size }
    }

    var unusedBytes: Int64 {
        unusedApps.reduce(0) { $0 + $1.size }
    }

    func category(_ kind: CleanCategory.Kind) -> CleanCategory? {
        categories.first { $0.kind == kind }
    }

    // MARK: Scanning

    /// Cheap enough to run on launch: one volume query, not a walk.
    func loadVolume() {
        volume = SystemScanner.volumeInfo()
        if volume != nil { measured.insert(.disk) }
    }

    // MARK: Restoring

    /// Brings back the last scan so launching shows real figures with a
    /// date on them, rather than a page of dashes.
    func restore() {

        hasFullDisk = DiskAccess.hasFullDisk
        cleanHistory = archive.events()
        loadQuarantine()

        guard let saved = archive.loadScan() else { return }

        lastScan = saved.lastScan
        scanCount = saved.scanCount
        measured = Set(saved.measured.compactMap(ScanScope.init(rawValue:)))

        if let total = saved.volumeTotal, let free = saved.volumeFree {
            volume = VolumeInfo(total: total, free: free)
        }

        categories = saved.categories.compactMap { record in
            guard let kind = CleanCategory.Kind(rawValue: record.kind) else { return nil }
            return CleanCategory(kind: kind, size: record.size, items: record.items)
        }

        apps = saved.apps.compactMap { record in
            let url = URL(fileURLWithPath: record.path)
            // An app uninstalled since the last scan shouldn't come back
            // from the archive as though it were still installed.
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return InstalledApp(
                url: url,
                name: record.name,
                size: record.size,
                version: record.version,
                bundleID: record.bundleID,
                lastUsed: record.lastUsed
            )
        }

        largeFiles = saved.largeFiles.compactMap { record in
            let url = URL(fileURLWithPath: record.path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return LargeFile(url: url, size: record.size)
        }

        // The disk moves constantly, so its figure is re-read rather than
        // restored. Everything else keeps the date it was measured.
        loadVolume()

        if !measured.isEmpty { phase = .finished }
    }

    /// Age of the figures on screen. The header shows it, because a cached
    /// number presented as current is worse than no number at all.
    var scanAge: TimeInterval? {
        lastScan.map { Date().timeIntervalSince($0) }
    }

    var isStale: Bool {
        (scanAge ?? 0) > 60 * 60 * 24
    }

    var freedAllTime: Int64 {
        cleanHistory.reduce(0) { $0 + $1.bytes }
    }

    private func persist() {

        var saved = ScanArchive()
        saved.lastScan = lastScan
        saved.scanCount = scanCount
        saved.volumeTotal = volume?.total
        saved.volumeFree = volume?.free
        saved.measured = measured.map(\.rawValue)

        saved.categories = categories.map {
            .init(kind: $0.kind.rawValue, size: $0.size, items: $0.items)
        }

        saved.apps = apps.map {
            .init(
                path: $0.url.path,
                name: $0.name,
                size: $0.size,
                version: $0.version,
                bundleID: $0.bundleID,
                lastUsed: $0.lastUsed
            )
        }

        saved.largeFiles = largeFiles.map {
            .init(path: $0.url.path, size: $0.size)
        }

        archive.save(saved)
    }

    /// Drops the archive without touching quarantine, which holds real files.
    func clearSavedData() {
        archive.clear()
        cleanHistory = []
        scanCount = 0
    }

    var storedBytes: Int64 { archive.storedBytes }

    func scan(_ scopes: Set<ScanScope> = ScanScope.everything) {

        guard !phase.isScanning, !scopes.isEmpty else { return }

        task?.cancel()

        let tasks = Self.tasks(for: scopes)
        guard !tasks.isEmpty else { return }

        steps = tasks.map {
            ScanStep(id: $0.id, title: $0.title, icon: $0.icon, weight: $0.weight)
        }

        let totalWeight = tasks.reduce(0) { $0 + $1.weight }

        task = Task { [weak self] in

            guard let self else { return }

            var done: Double = 0

            for (index, work) in tasks.enumerated() {

                if Task.isCancelled { return }

                await self.begin(step: index, progress: done / totalWeight, label: work.title)
                await self.run(work)

                done += work.weight
                await self.complete(step: index, progress: done / totalWeight)
            }

            if Task.isCancelled { return }

            await self.finish(scopes: scopes)
        }
    }

    /// Expands the requested scopes into the individual folders that will
    /// actually be measured, skipping the ones this Mac doesn't have, so
    /// the step list is the truth rather than a menu of possibilities.
    private static func tasks(for scopes: Set<ScanScope>) -> [ScanTask] {

        var tasks: [ScanTask] = []

        if scopes.contains(.disk) { tasks.append(.disk) }

        if scopes.contains(.cleanable) {

            let fullDisk = DiskAccess.hasFullDisk

            for kind in CleanCategory.Kind.allCases {

                let folder = SystemCleaner.root(for: kind)

                guard FileManager.default.fileExists(atPath: folder.path) else { continue }

                // Downloads is measured only when macOS will allow it
                // quietly. Otherwise the scan would prompt every time.
                if !fullDisk, DiskAccess.isProtected(folder) { continue }

                tasks.append(.category(kind))
            }
        }

        if scopes.contains(.applications) { tasks.append(.applications) }
        if scopes.contains(.orphans) { tasks.append(.orphans) }
        if scopes.contains(.duplicates) { tasks.append(.duplicates) }
        if scopes.contains(.largeFiles) { tasks.append(.largeFiles) }

        return tasks
    }

    private func begin(step index: Int, progress: Double, label: String) {
        guard steps.indices.contains(index) else { return }
        steps[index].state = .running
        phase = .scanning(progress: progress, label: label)
    }

    private func complete(step index: Int, progress: Double) {
        guard steps.indices.contains(index) else { return }
        steps[index].state = .done
        if case .scanning(_, let label) = phase {
            phase = .scanning(progress: progress, label: label)
        }
    }

    private func run(_ work: ScanTask) async {

        switch work {

        case .disk:
            volume = await Self.offMain { SystemScanner.volumeInfo() }

        case .category(let kind):
            let measured = await Self.offMain {
                SystemScanner.cleanCategory(kind) { Task.isCancelled }
            }
            if let measured {
                categories.removeAll { $0.kind == kind }
                categories.append(measured)
            }

        case .applications:
            apps = await Self.offMain {
                SystemScanner.installedApps { Task.isCancelled }
            }

        case .orphans:
            orphans = await Self.offMain {
                OrphanFinder.find { Task.isCancelled }
            }

        case .duplicates:
            duplicates = await Self.offMain {
                DuplicateFinder.find(isCancelled: { Task.isCancelled })
            }

        case .largeFiles:
            let skip = !DiskAccess.hasFullDisk
            largeFiles = await Self.offMain {
                SystemScanner.largeFiles(skipProtected: skip) { Task.isCancelled }
            }
        }
    }

    // MARK: Cleaning

    /// Moves the chosen categories to the Trash, then re-measures so the
    /// page stops reporting space that has already been freed.
    func clean(
        _ kinds: Set<CleanCategory.Kind>,
        mode: RemovalMode = .trash,
        emptyTrash: Bool = false,
        keeping: Set<URL> = []
    ) {

        guard !isCleaning, !phase.isScanning, !kinds.isEmpty else { return }

        isCleaning = true
        cleanProgress = 0
        lastCleanMode = mode

        task?.cancel()

        task = Task { [weak self] in

            guard let self else { return }

            var total = CleanResult()
            let ordered = CleanCategory.Kind.allCases.filter { kinds.contains($0) }

            for (index, kind) in ordered.enumerated() {

                if Task.isCancelled { break }

                await self.setCleanProgress(Double(index) / Double(ordered.count))

                let result = await Self.offMain {
                    SystemCleaner.clean(
                        kind,
                        mode: mode,
                        allowPermanent: emptyTrash,
                        keeping: keeping,
                        isCancelled: { Task.isCancelled }
                    )
                }

                total = total + result
            }

            await self.finishCleaning(total)
            self.scan([.disk, .cleanable])
        }
    }

    private func setCleanProgress(_ value: Double) {
        cleanProgress = value
    }

    private func finishCleaning(_ result: CleanResult) {

        lastClean = result
        lastCleanAt = Date()
        isCleaning = false
        cleanProgress = 1
        showsCleanResult = result.removed > 0 || result.failed > 0

        if result.removed > 0 || result.failed > 0 {
            cleanHistory = archive.append(
                CleanEvent(
                    removed: result.removed,
                    bytes: result.bytes,
                    failed: result.failed,
                    mode: lastCleanMode.rawValue
                )
            )
        }

        loadQuarantine()
        persist()
    }

    // MARK: Quarantine

    /// What aged out on this launch, so the UI can mention it once.
    @Published private(set) var expiredOnLaunch: CleanResult?

    func loadQuarantine() {

        // Ages items out before reading, so the list never shows something
        // that is about to vanish without explanation.
        let purged = quarantine.purgeExpired()

        if purged.removed > 0 {
            expiredOnLaunch = purged
        }

        quarantined = quarantine.entries()
    }

    func dismissExpiryNotice() {
        expiredOnLaunch = nil
    }

    var quarantinedBytes: Int64 {
        quarantined.reduce(0) { $0 + $1.size }
    }

    /// Returns the error rather than swallowing it: a restore that quietly
    /// does nothing is worse than one that says why it couldn't.
    @discardableResult
    func restore(_ entry: QuarantineEntry) -> String? {
        do {
            try quarantine.restore(entry)
            loadQuarantine()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func storedURL(for entry: QuarantineEntry) -> URL {
        quarantine.storedURL(for: entry)
    }

    func purge(_ entry: QuarantineEntry) {
        try? quarantine.purge(entry)
        loadQuarantine()
    }

    func purgeAll() {
        try? quarantine.purgeAll()
        loadQuarantine()
    }

    /// Leftovers go to quarantine like everything else, so a wrong guess
    /// by the finder costs a click to undo rather than a lost file.
    func removeOrphans(_ urls: Set<URL>) {

        guard !isCleaning, !urls.isEmpty else { return }

        isCleaning = true
        cleanProgress = 0
        lastCleanMode = .quarantine

        let sizes = Dictionary(
            uniqueKeysWithValues: orphans.map { ($0.url, $0.size) }
        )
        let labels = Dictionary(
            uniqueKeysWithValues: orphans.map { ($0.url, $0.identifier) }
        )

        task?.cancel()

        task = Task { [weak self] in

            guard let self else { return }

            var result = CleanResult()

            for (index, url) in urls.enumerated() {

                if Task.isCancelled { break }

                await self.setCleanProgress(Double(index) / Double(urls.count))

                do {
                    try Quarantine.shared.store(
                        url,
                        label: labels[url] ?? "Leftover",
                        size: sizes[url] ?? 0
                    )
                    result.removed += 1
                    result.bytes += sizes[url] ?? 0
                } catch {
                    result.failed += 1
                }
            }

            await self.finishCleaning(result)
            self.scan([.disk, .orphans])
        }
    }

    /// Copies go to quarantine like everything else. The set they came
    /// from is re-measured afterwards, so a group that is down to one file
    /// stops being reported as a duplicate.
    func removeDuplicates(_ urls: Set<URL>) {

        guard !isCleaning, !urls.isEmpty else { return }

        isCleaning = true
        cleanProgress = 0
        lastCleanMode = .quarantine

        var sizes: [URL: Int64] = [:]
        for set in duplicates {
            for file in set.files { sizes[file] = set.size }
        }

        task?.cancel()

        task = Task { [weak self] in

            guard let self else { return }

            var result = CleanResult()

            for (index, url) in urls.enumerated() {

                if Task.isCancelled { break }

                await self.setCleanProgress(Double(index) / Double(urls.count))

                do {
                    try Quarantine.shared.store(
                        url,
                        label: "Duplicate",
                        size: sizes[url] ?? 0
                    )
                    result.removed += 1
                    result.bytes += sizes[url] ?? 0
                } catch {
                    result.failed += 1
                }
            }

            await self.finishCleaning(result)
            self.scan([.disk, .duplicates])
        }
    }

    /// Large files are the user's own documents, so this removes exactly
    /// what was ticked and nothing near it.
    func removeLargeFiles(_ urls: Set<URL>) {

        guard !isCleaning, !urls.isEmpty else { return }

        isCleaning = true
        cleanProgress = 0
        lastCleanMode = .quarantine

        let sizes = Dictionary(
            uniqueKeysWithValues: largeFiles.map { ($0.url, $0.size) }
        )

        task?.cancel()

        task = Task { [weak self] in

            guard let self else { return }

            var result = CleanResult()

            for (index, url) in urls.enumerated() {

                if Task.isCancelled { break }

                await self.setCleanProgress(Double(index) / Double(urls.count))

                do {
                    try Quarantine.shared.store(
                        url,
                        label: url.lastPathComponent,
                        size: sizes[url] ?? 0
                    )
                    result.removed += 1
                    result.bytes += sizes[url] ?? 0
                } catch {
                    result.failed += 1
                }
            }

            await self.finishCleaning(result)
            self.scan([.disk, .largeFiles])
        }
    }

    // MARK: Uninstalling

    /// Builds the plan off the main actor: sizing a dozen support folders
    /// is the same kind of walk as a scan.
    func uninstallPlan(for app: InstalledApp) async -> UninstallPlan {

        let leftovers = await Self.offMain {
            AppUninstaller.leftovers(for: app)
        }

        return UninstallPlan(
            app: app,
            bundleID: AppUninstaller.bundleID(of: app.url),
            leftovers: leftovers
        )
    }

    /// Everything an uninstall removes goes to quarantine, never straight
    /// out: an app's files come from a dozen paths, and only the manifest
    /// knows how to put them back.
    func uninstall(_ plan: UninstallPlan, items: [URL]) {

        guard !isCleaning else { return }

        // Refused here as well as in the sheet: the rule belongs with the
        // action, not only with the screen that happens to offer it today.
        guard !AppUninstaller.isProtected(plan.app) else { return }

        isCleaning = true
        cleanProgress = 0

        let label = plan.app.name
        let sizes = Dictionary(
            uniqueKeysWithValues: plan.leftovers.map { ($0.url, $0.size) }
        )
        let appSize = plan.app.size
        lastCleanMode = .quarantine

        task?.cancel()

        task = Task { [weak self] in

            guard let self else { return }

            var result = CleanResult()

            for (index, url) in items.enumerated() {

                if Task.isCancelled { break }

                await self.setCleanProgress(Double(index) / Double(items.count))

                let size = sizes[url] ?? appSize

                do {
                    try Quarantine.shared.store(url, label: label, size: size)
                    result.removed += 1
                    result.bytes += size
                } catch {
                    result.failed += 1
                }
            }

            await self.finishCleaning(result)
            self.scan([.disk, .applications])
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isCleaning = false
        steps = []
        phase = measured.isEmpty ? .idle : .finished
    }

    // MARK: Plumbing

    /// The walks are synchronous and long. They must not run on the main
    /// actor, or the window stops redrawing while the bar is meant to move.
    private static func offMain<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await Task.detached(priority: .utility) { work() }.value
    }

    private func set(phase: Phase) { self.phase = phase }

    private func finish(scopes: Set<ScanScope>) {
        steps = []
        measured.formUnion(scopes)
        lastScan = Date()
        scanCount += 1
        phase = .finished
        // Written once per scan, not per step: ten writes during one scan
        // would be ten times the disk churn for the same result.
        persist()
        // Paths come and go as things are cleaned, so icons are re-resolved
        // after a scan rather than cached for the life of the process.
        AppIcons.forget()
    }
}
