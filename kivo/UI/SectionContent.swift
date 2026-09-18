import SwiftUI

// MARK: - Page content
//
// Every screen is the same layout with different content, so the content is
// built here from the live ScanStore and there is one page view.
//
// Nothing in this file invents a number. A figure Kivo has not measured
// shows a dash, and each value is gated on the scope that produces it, so a
// page can't borrow another page's freshness.

struct SectionScope: Identifiable {

    let id = UUID()
    let icon: String
    let title: String
    var state: String?
}

struct SectionTile: Identifiable {

    let id = UUID()
    let icon: String

    /// The file this tile stands for, for its icon and its context menu.
    var fileURL: URL?
    let title: String
    let value: String
    let detail: String
    var pillText: String?
    var pillTint: Color = .kivoAccent
    var fraction: Double?
    var barTint: Color = .kivoAccent

    /// Shown behind the i button on the card.
    var info: String?
}

struct SectionPageConfig {

    let headline: String
    let subline: String

    let primaryTitle: String
    let primaryIcon: String

    /// What this page's button actually reads. Empty means the button
    /// navigates instead.
    var scanScopes: Set<ScanScope> = ScanScope.everything
    var primaryOpens: SidebarSection?

    /// Offers the Clean button beside the scan. Only the Clean page does,
    /// so removal has one home rather than a button on every screen.
    var offersClean: Bool = false

    /// The same idea for leftovers, whose review sheet is a different one
    /// because nothing in it starts selected.
    var offersReview: Bool = false

    /// And for duplicates, which group their files rather than listing them.
    var offersDuplicates: Bool = false

    /// And for large files, the last page that could only look.
    var offersLargeFiles: Bool = false

    let scope: [SectionScope]
    let scopeState: String

    let metricLabel: String
    let metricValue: String

    /// Behind the i button on the hero: what this page's scan looks at.
    let info: String

    let tiles: [SectionTile]

    let listTitle: String
    let listRows: [ActivityRow.Model]

    let sideActions: [SidebarSection]
}

// MARK: - Short labels for the action tiles

extension SidebarSection {

    var actionSubtitle: String {
        switch self {
        case .diskMap: "See the shape of the disk"
        case .quarantine: "Put removed things back"
        case .overview: "See the whole Mac at once"
        case .clean: "Caches, logs and the Trash"
        case .leftovers: "Files from apps you removed"
        case .duplicates: "The same file, kept twice"
        case .applications: "What's installed, by size"
        case .storage: "How the disk is filled"
        case .largeFiles: "Files over 1 GB"
        case .activity: "What Kivo has done"
        }
    }

    var actionIcon: String {
        switch self {
        case .diskMap: "square.grid.3x3.topleft.filled"
        case .quarantine: "tray.full.fill"
        case .overview: "square.grid.2x2.fill"
        case .clean: "sparkles"
        case .leftovers: "shippingbox.fill"
        case .duplicates: "doc.on.doc.fill"
        case .applications: "square.stack.3d.up.fill"
        case .storage: "internaldrive.fill"
        case .largeFiles: "doc.fill"
        case .activity: "clock.arrow.circlepath"
        }
    }
}

// MARK: - Building a page from live data

extension SectionPageConfig {

    /// Reads the store, which is main-actor state. SwiftUI builds view
    /// bodies there anyway, so this is where it belongs.
    @MainActor
    static func config(
        for section: SidebarSection,
        store: ScanStore,
        onSelectApp: ((InstalledApp) -> Void)? = nil
    ) -> SectionPageConfig {

        let dash = "—"

        /// A measured value, or a dash while that part is unmeasured.
        func value(
            _ scope: ScanScope,
            _ text: @autoclosure () -> String
        ) -> String {
            store.has(scope) ? text() : dash
        }

        func count(
            _ scope: ScanScope,
            _ number: @autoclosure () -> Int,
            _ noun: String
        ) -> String {
            guard store.has(scope) else { return dash }
            let n = number()
            return "\(n) \(noun)\(n == 1 ? "" : "s")"
        }

        let lastScan: String = {
            guard let date = store.lastScan else { return "No scan yet" }
            return "Scanned \(date.formatted(date: .omitted, time: .shortened))"
        }()

        switch section {

        case .overview:

            let cleanable = store.has(.cleanable)

            return SectionPageConfig(
                headline: cleanable
                    ? (store.cleanableBytes > 0
                        ? "\(store.cleanableBytes.byteLabel) can be freed"
                        : "Nothing to clean up")
                    : "Ready when you are",
                subline: cleanable
                    ? "\(lastScan). Caches, logs and the Trash, measured on this disk."
                    : "A scan measures the disk, the cache folders, your apps and any file over 1 GB.",
                primaryTitle: store.hasScanned ? "Scan Again" : "Scan Everything",
                primaryIcon: "shield.lefthalf.filled",
                scanScopes: ScanScope.everything,
                scope: [
                    .init(
                        icon: "internaldrive.fill",
                        title: "Caches",
                        state: value(.cleanable, store.category(.caches)?.size.byteLabel ?? dash)
                    ),
                    .init(
                        icon: "doc.text",
                        title: "Logs",
                        state: value(.cleanable, store.category(.logs)?.size.byteLabel ?? dash)
                    ),
                    .init(
                        icon: "trash",
                        title: "Trash",
                        state: value(.cleanable, store.category(.trash)?.size.byteLabel ?? dash)
                    )
                ],
                scopeState: dash,
                metricLabel: "Safe to clean",
                metricValue: value(.cleanable, store.cleanableBytes.byteLabel),
                info: """
                    A full scan reads the disk, measures the cache, log, \
                    Trash and Downloads folders, sizes every app in \
                    /Applications, and lists files of 1 GB or more in your \
                    home folder. It only reads. Kivo cannot delete anything yet.
                    """,
                tiles: [
                    .init(
                        icon: "internaldrive.fill",
                        title: "Storage",
                        value: store.volume?.used.byteLabel ?? dash,
                        detail: store.volume.map { "of \($0.total.byteLabel) used" }
                            ?? "startup disk",
                        pillText: store.volume.map { "\(Int($0.fraction * 100))% full" },
                        pillTint: quietUnlessBusy(store.volume?.fraction),
                        fraction: store.volume?.fraction,
                        barTint: quietUnlessBusy(store.volume?.fraction),
                        info: diskInfo
                    ),
                    // Not "safe to clean" again: the hero above already
                    // leads with that figure, and a card repeating it is a
                    // slot the page could have spent on something else.
                    .init(
                        icon: "square.stack.3d.up.fill",
                        title: "Applications",
                        value: value(.applications, store.appsBytes.byteLabel),
                        detail: store.has(.applications)
                            ? count(.applications, store.apps.count, "app") + " installed"
                            : "not measured yet",
                        info: "Every app bundle in /Applications and ~/Applications, sized on disk."
                    ),
                    .init(
                        icon: "doc.fill",
                        title: "Large Files",
                        value: value(.largeFiles, store.largeFileBytes.byteLabel),
                        detail: "files of 1 GB or more",
                        pillText: store.has(.largeFiles)
                            ? count(.largeFiles, store.largeFiles.count, "file")
                            : nil,
                        info: largeFileInfo
                    )
                ],
                listTitle: "Biggest items",
                listRows: store.largeFiles.prefix(8).map { file in
                    .init(
                        icon: "doc",
                        fileURL: file.url,
                        title: file.name,
                        detail: shortPath(file.url),
                        value: file.size.byteLabel,
                        sortValue: file.size,
                        safety: .check
                    )
                }.emptyFallback(
                    .init(
                        icon: "shield.lefthalf.filled",
                        title: "Large files",
                        detail: store.has(.largeFiles)
                            ? "No file in your home folder reaches 1 GB"
                            : "Scan to list the biggest files on this Mac",
                        value: dash
                    )
                ),
                sideActions: [.clean, .storage, .applications]
            )

        case .clean:

            let cleanable = store.has(.cleanable)
            let safe = store.categories(.safe)
            let biggest = store.categories.sorted { $0.size > $1.size }

            return SectionPageConfig(
                headline: cleanable
                    ? (store.cleanableBytes > 0
                        ? "\(store.cleanableBytes.byteLabel) is safe to clear"
                        : "Nothing to clear")
                    : "Ready when you are",
                subline: cleanable
                    ? sublineForClean(store)
                    : "A scan measures the folders your Mac and your tools rebuild by themselves.",
                primaryTitle: cleanable ? "Scan Again" : "Scan Caches",
                primaryIcon: "sparkles",
                scanScopes: [.disk, .cleanable],
                offersClean: true,
                scope: safe.prefix(3).map { category in
                    SectionScope(
                        icon: category.icon,
                        title: category.title,
                        state: category.size.byteLabel
                    )
                },
                scopeState: dash,
                metricLabel: "Safe to clean",
                metricValue: value(.cleanable, store.cleanableBytes.byteLabel),
                info: """
                    Kivo sorts every folder into three groups. Safe ones \
                    rebuild themselves and make up the figure above. Some \
                    can go but cost a re-download, so they are never ticked \
                    for you. The rest are yours, or belong to a tool that \
                    should do its own deleting, and Kivo only measures them.
                    """,
                tiles: cleanable && !biggest.isEmpty
                    ? biggest.prefix(3).map { category in
                        SectionTile(
                            icon: category.icon,
                            title: category.title,
                            value: category.size.byteLabel,
                            detail: category.detail,
                            pillText: category.tier.pill,
                            pillTint: tierTint(category.tier),
                            info: category.kind.manualNote
                        )
                    }
                    : [
                        .init(icon: "internaldrive.fill", title: "Safe to clean",
                              value: dash, detail: "not measured yet"),
                        .init(icon: "shippingbox", title: "Rebuilds",
                              value: dash, detail: "not measured yet"),
                        .init(icon: "person.crop.circle", title: "Left to you",
                              value: dash, detail: "not measured yet")
                    ],
                listTitle: "Every folder Kivo checked",
                listRows: biggest.map { category in
                    ActivityRow.Model(
                        icon: category.icon,
                        fileURL: SystemCleaner.root(for: category.kind),
                        title: category.title,
                        badge: category.tier.pill,
                        detail: "\(category.items) item\(category.items == 1 ? "" : "s") · \(category.detail)",
                        value: category.size.byteLabel,
                        sortValue: category.size,
                        safety: safety(for: category.tier)
                    )
                }.emptyFallback(
                    .init(
                        icon: "sparkles",
                        title: "Nothing measured",
                        detail: "Scan to see what can be cleared",
                        value: dash
                    )
                ),
                sideActions: [.storage, .largeFiles, .applications]
            )

        case .leftovers:

            let scanned = store.has(.orphans)
            let biggest = store.orphans.prefix(3)

            return SectionPageConfig(
                headline: scanned
                    ? (store.orphans.isEmpty
                        ? "Nothing left behind"
                        : "\(store.orphanBytes.byteLabel) from apps you no longer have")
                    : "Ready when you are",
                subline: scanned
                    ? "\(store.orphans.count) folder\(store.orphans.count == 1 ? "" : "s") name an app that isn't installed. Check the list before removing any."
                    : "A scan looks for support files whose app has gone.",
                primaryTitle: scanned ? "Scan Again" : "Find Leftovers",
                primaryIcon: "shippingbox.fill",
                scanScopes: [.orphans],
                offersReview: scanned && !store.orphans.isEmpty,
                scope: [
                    .init(
                        icon: "shippingbox",
                        title: "Found",
                        state: count(.orphans, store.orphans.count, "folder")
                    ),
                    .init(
                        icon: "internaldrive",
                        title: "Total",
                        state: value(.orphans, store.orphanBytes.byteLabel)
                    ),
                    .init(
                        icon: "arrow.up.doc",
                        title: "Largest",
                        state: value(.orphans, store.orphans.first?.size.byteLabel ?? dash)
                    )
                ],
                scopeState: dash,
                metricLabel: "Leftovers",
                metricValue: value(.orphans, store.orphanBytes.byteLabel),
                info: """
                    Kivo reads the name of each folder in your Library and \
                    asks macOS whether an app with that identifier is \
                    installed anywhere. Only reverse-DNS names are \
                    considered, Apple's own are never listed, and a folder \
                    is left alone if any app from the same vendor is still \
                    installed. Even so these are guesses, so nothing is \
                    selected for you and everything removed can be put back.
                    """,
                tiles: scanned && !biggest.isEmpty
                    ? biggest.map { orphan in
                        SectionTile(
                            icon: "shippingbox.fill",
                            title: orphan.identifier,
                            value: orphan.size.byteLabel,
                            detail: orphan.kind.lowercased(),
                            pillText: "No app",
                            pillTint: .kivoWarn
                        )
                    }
                    : [
                        .init(icon: "shippingbox.fill", title: "Leftovers",
                              value: dash, detail: "not scanned yet"),
                        .init(icon: "internaldrive", title: "Reclaimable",
                              value: dash, detail: "not scanned yet"),
                        .init(icon: "arrow.up.doc", title: "Largest",
                              value: dash, detail: "not scanned yet")
                    ],
                listTitle: "Every leftover found",
                listRows: store.orphans.prefix(14).map { orphan in
                    ActivityRow.Model(
                        icon: "shippingbox",
                        fileURL: orphan.url,
                        title: orphan.identifier,
                        badge: orphan.kind,
                        detail: orphan.shortPath,
                        value: orphan.size.byteLabel,
                        sortValue: orphan.size,
                        safety: .check
                    )
                }.emptyFallback(
                    .init(
                        icon: "shippingbox",
                        title: "Leftovers",
                        detail: scanned
                            ? "Every folder here belongs to an app you still have"
                            : "Scan to look for files from apps you removed",
                        value: dash
                    )
                ),
                sideActions: [.applications, .clean, .quarantine]
            )

        case .duplicates:

            let scanned = store.has(.duplicates)
            let biggest = store.duplicates.prefix(3)

            return SectionPageConfig(
                headline: scanned
                    ? (store.duplicates.isEmpty
                        ? "No duplicates found"
                        : "\(store.duplicateBytes.byteLabel) held in copies")
                    : "Ready when you are",
                subline: scanned
                    ? "\(store.duplicates.count) set\(store.duplicates.count == 1 ? "" : "s") of identical files across \(store.duplicateFileCount) copies. Keeping one of each frees the rest."
                    : "A scan compares files by content, not by name.",
                primaryTitle: scanned ? "Scan Again" : "Find Duplicates",
                primaryIcon: "doc.on.doc.fill",
                scanScopes: [.duplicates],
                offersDuplicates: scanned && !store.duplicates.isEmpty,
                scope: [
                    .init(
                        icon: "doc.on.doc",
                        title: "Sets",
                        state: count(.duplicates, store.duplicates.count, "set")
                    ),
                    .init(
                        icon: "doc",
                        title: "Copies",
                        state: count(.duplicates, store.duplicateFileCount, "file")
                    ),
                    .init(
                        icon: "internaldrive",
                        title: "Reclaimable",
                        state: value(.duplicates, store.duplicateBytes.byteLabel)
                    )
                ],
                scopeState: dash,
                metricLabel: "Duplicates",
                metricValue: value(.duplicates, store.duplicateBytes.byteLabel),
                info: """
                    Files are grouped by size first, then compared by a hash \
                    of their contents, so a match is identical rather than \
                    similarly named. Hard links and clones count once, since \
                    removing one frees nothing. Dependency and build folders \
                    are skipped: three copies of a package in three projects \
                    are three projects working, not wasted space.
                    """,
                tiles: scanned && !biggest.isEmpty
                    ? biggest.map { set in
                        SectionTile(
                            icon: "doc.on.doc.fill",
                            fileURL: set.files.first,
                            title: set.name,
                            value: set.reclaimable.byteLabel,
                            detail: "\(set.files.count) copies of \(set.size.byteLabel)",
                            pillText: "\(set.files.count)×",
                            pillTint: .kivoWarn
                        )
                    }
                    : [
                        .init(icon: "doc.on.doc.fill", title: "Duplicates",
                              value: dash, detail: "not scanned yet"),
                        .init(icon: "doc", title: "Copies",
                              value: dash, detail: "not scanned yet"),
                        .init(icon: "internaldrive", title: "Reclaimable",
                              value: dash, detail: "not scanned yet")
                    ],
                listTitle: "Every set found",
                listRows: store.duplicates.prefix(14).map { set in
                    ActivityRow.Model(
                        icon: "doc.on.doc",
                        fileURL: set.files.first,
                        title: set.name,
                        badge: "\(set.files.count)×",
                        detail: set.files.first?.deletingLastPathComponent().path
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "",
                        value: set.reclaimable.byteLabel,
                        sortValue: set.reclaimable,
                        safety: .safe
                    )
                }.emptyFallback(
                    .init(
                        icon: "doc.on.doc",
                        title: "Duplicates",
                        detail: scanned
                            ? "Nothing on this Mac is stored twice"
                            : "Scan to compare files by content",
                        value: dash
                    )
                ),
                sideActions: [.largeFiles, .clean, .quarantine]
            )

        case .applications:

            let scanned = store.has(.applications)

            return SectionPageConfig(
                headline: scanned
                    ? count(.applications, store.apps.count, "app") + " installed"
                    : "Ready when you are",
                subline: scanned
                    ? sublineForApps(store)
                    : "A scan sizes every app bundle and reads when each was last opened.",
                primaryTitle: scanned ? "Scan Again" : "Scan Apps",
                primaryIcon: "square.stack.3d.up.fill",
                scanScopes: [.applications],
                scope: [
                    .init(
                        icon: "square.stack.3d.up",
                        title: "Installed",
                        state: count(.applications, store.apps.count, "app")
                    ),
                    .init(
                        icon: "internaldrive",
                        title: "Total",
                        state: value(.applications, store.appsBytes.byteLabel)
                    ),
                    .init(
                        icon: "clock",
                        title: "Unused",
                        state: store.has(.applications)
                            ? (store.unusedApps.isEmpty
                                ? "None"
                                : "\(store.unusedApps.count) · \(store.unusedBytes.byteLabel)")
                            : dash
                    )
                ],
                scopeState: dash,
                metricLabel: "Applications",
                metricValue: value(.applications, store.appsBytes.byteLabel),
                info: """
                    Sizes every .app bundle in /Applications and \
                    ~/Applications. The figure is what the bundle takes on \
                    disk, which is not the same as what removing it would \
                    free: an app's caches and support files live elsewhere.
                    """,
                tiles: tiles(
                    from: store.apps.prefix(3).map {
                        ($0.name, $0.size, $0.url, "opened \(usageLabel($0))")
                    },
                    icon: "square.stack.3d.up.fill",
                    detail: "on disk",
                    measured: scanned,
                    emptyTitle: "Applications"
                ),
                listTitle: "Installed apps",
                listRows: store.apps.prefix(14).map { app in
                    .init(
                        icon: "app",
                        fileURL: app.url,
                        title: app.name,
                        badge: app.version,
                        detail: shortPath(app.url),
                        value: app.size.byteLabel,
                        sortValue: app.size,
                        onSelect: onSelectApp.map { select in { select(app) } }
                    )
                }.emptyFallback(
                    .init(
                        icon: "app",
                        title: "Applications",
                        detail: scanned ? "No other apps found" : "Not measured yet",
                        value: dash
                    )
                ),
                sideActions: [.clean, .storage, .activity]
            )

        case .storage:

            let volume = store.volume

            return SectionPageConfig(
                headline: volume.map {
                    "\($0.used.byteLabel) of \($0.total.byteLabel) used"
                } ?? "Disk not read yet",
                subline: volume.map {
                    "\($0.free.byteLabel) free on this Mac."
                } ?? "A scan reads the startup disk.",
                primaryTitle: store.has(.cleanable) ? "Scan Again" : "Scan Disk",
                primaryIcon: "internaldrive.fill",
                scanScopes: [.disk, .cleanable],
                scope: [
                    .init(icon: "internaldrive", title: "Used", state: volume?.used.byteLabel ?? dash),
                    .init(icon: "externaldrive", title: "Free", state: volume?.free.byteLabel ?? dash),
                    .init(
                        icon: "sparkles",
                        title: "Safe to clean",
                        state: value(.cleanable, store.cleanableBytes.byteLabel)
                    )
                ],
                scopeState: dash,
                metricLabel: "Used",
                metricValue: volume?.used.byteLabel ?? dash,
                info: diskInfo,
                tiles: [
                    .init(
                        icon: "internaldrive.fill",
                        title: "Used",
                        value: volume?.used.byteLabel ?? dash,
                        detail: volume.map { "of \($0.total.byteLabel)" } ?? "capacity",
                        pillText: volume.map { "\(Int($0.fraction * 100))% full" },
                        pillTint: diskTint(volume?.fraction),
                        fraction: volume?.fraction,
                        barTint: diskTint(volume?.fraction)
                    ),
                    .init(
                        icon: "externaldrive",
                        title: "Free",
                        value: volume?.free.byteLabel ?? dash,
                        detail: "available now",
                        pillText: volume == nil ? nil : "Live",
                        pillTint: .kivoGood,
                        info: diskInfo
                    ),
                    .init(
                        icon: "square.stack.3d.up.fill",
                        title: "Applications",
                        value: value(.applications, store.appsBytes.byteLabel),
                        detail: store.has(.applications)
                            ? count(.applications, store.apps.count, "app") + " installed"
                            : "scan Applications to measure",
                        info: "Measured on the Applications page. A disk scan leaves it alone, since sizing every bundle takes far longer than reading the volume."
                    )
                ],
                listTitle: "Biggest contributors",
                listRows: [
                    .init(
                        icon: "sparkles",
                        title: "Caches, logs and Trash",
                        detail: "Rebuildable data",
                        value: value(.cleanable, store.cleanableBytes.byteLabel),
                        sortValue: store.cleanableBytes
                    ),
                    .init(
                        icon: "doc.fill",
                        title: "Files of 1 GB or more",
                        detail: store.has(.largeFiles)
                            ? count(.largeFiles, store.largeFiles.count, "file") + " in your home folder"
                            : "Scan Large Files to measure",
                        value: value(.largeFiles, store.largeFileBytes.byteLabel),
                        sortValue: store.largeFileBytes
                    ),
                    .init(
                        icon: "square.stack.3d.up",
                        title: "Applications",
                        detail: store.has(.applications)
                            ? count(.applications, store.apps.count, "app") + " in /Applications"
                            : "Scan Applications to measure",
                        value: value(.applications, store.appsBytes.byteLabel),
                        sortValue: store.appsBytes
                    )
                ],
                sideActions: [.largeFiles, .clean, .applications]
            )

        case .largeFiles:

            let scanned = store.has(.largeFiles)

            return SectionPageConfig(
                headline: scanned
                    ? (store.largeFiles.isEmpty
                        ? "No file reaches 1 GB"
                        : "\(store.largeFileBytes.byteLabel) in large files")
                    : "Ready when you are",
                subline: scanned
                    ? "Files of 1 GB or more in your home folder, biggest first."
                    : "A scan walks your home folder for files of 1 GB or more.",
                primaryTitle: scanned ? "Scan Again" : "Scan Files",
                primaryIcon: "doc.fill",
                scanScopes: [.largeFiles],
                offersLargeFiles: scanned && !store.largeFiles.isEmpty,
                scope: [
                    .init(
                        icon: "doc",
                        title: "Found",
                        state: count(.largeFiles, store.largeFiles.count, "file")
                    ),
                    .init(
                        icon: "internaldrive",
                        title: "Total",
                        state: value(.largeFiles, store.largeFileBytes.byteLabel)
                    ),
                    .init(
                        icon: "arrow.up.doc",
                        title: "Largest",
                        state: value(.largeFiles, store.largeFiles.first?.size.byteLabel ?? dash)
                    )
                ],
                scopeState: dash,
                metricLabel: "Large files",
                metricValue: value(.largeFiles, store.largeFileBytes.byteLabel),
                info: largeFileInfo,
                tiles: tiles(
                    from: store.largeFiles.prefix(3).map { ($0.name, $0.size, $0.url, nil) },
                    icon: "doc.fill",
                    detail: "on disk",
                    measured: scanned,
                    emptyTitle: "Large files"
                ),
                listTitle: "Next largest",
                listRows: store.largeFiles.dropFirst(3).prefix(10).map { file in
                    .init(
                        icon: "doc",
                        fileURL: file.url,
                        title: file.name,
                        detail: shortPath(file.url),
                        value: file.size.byteLabel
                    )
                }.emptyFallback(
                    .init(
                        icon: "doc",
                        title: "Large files",
                        detail: scanned ? "Nothing else reaches 1 GB" : "Not measured yet",
                        value: dash
                    )
                ),
                sideActions: [.storage, .clean, .activity]
            )

        case .diskMap:

            // DiskMapView draws this screen itself.
            return SectionPageConfig(
                headline: "Disk Map",
                subline: "Every folder drawn to scale.",
                primaryTitle: "Go to Dashboard",
                primaryIcon: "square.grid.2x2.fill",
                scanScopes: [],
                primaryOpens: .overview,
                scope: [],
                scopeState: dash,
                metricLabel: "Disk",
                metricValue: dash,
                info: "A treemap of one folder at a time.",
                tiles: [],
                listTitle: "Folders",
                listRows: [],
                sideActions: [.storage, .largeFiles, .clean]
            )

        case .quarantine:

            // QuarantineView draws this screen itself; the config exists so
            // the switch stays exhaustive when a section is added.
            return SectionPageConfig(
                headline: "Removed Items",
                subline: "Things Kivo took away. Put any of them back.",
                primaryTitle: "Go to Dashboard",
                primaryIcon: "square.grid.2x2.fill",
                scanScopes: [],
                primaryOpens: .overview,
                scope: [],
                scopeState: dash,
                metricLabel: "Set aside",
                metricValue: dash,
                info: "Things Kivo has taken away but not deleted.",
                tiles: [],
                listTitle: "Held",
                listRows: [],
                sideActions: [.clean, .applications, .overview]
            )

        case .activity:

            let scans = store.scanCount
            let cleanups = store.cleanHistory.count

            return SectionPageConfig(
                headline: scans == 0
                    ? "No activity yet"
                    : "\(store.freedAllTime.byteLabel) freed so far",
                subline: scans == 0
                    ? "Scans and cleanups show up here once you've run one."
                    : "\(scans) scan\(scans == 1 ? "" : "s") and \(cleanups) cleanup\(cleanups == 1 ? "" : "s"), kept between launches.",
                primaryTitle: "Go to Dashboard",
                primaryIcon: "square.grid.2x2.fill",
                scanScopes: [],
                primaryOpens: .overview,
                scope: [
                    .init(icon: "magnifyingglass", title: "Scans", state: "\(scans)"),
                    .init(icon: "sparkles", title: "Cleanups", state: "\(cleanups)"),
                    .init(
                        icon: "tray.full",
                        title: "Set aside",
                        state: store.quarantined.isEmpty
                            ? "None"
                            : store.quarantinedBytes.byteLabel
                    )
                ],
                scopeState: dash,
                metricLabel: "Freed so far",
                metricValue: store.freedAllTime.byteLabel,
                info: """
                    Kivo keeps the last scan and a log of every cleanup in \
                    Application Support. Both are small, capped, and can be \
                    cleared from Settings. Nothing here is sent anywhere.
                    """,
                tiles: [
                    .init(
                        icon: "magnifyingglass",
                        title: "Scans",
                        value: "\(scans)",
                        detail: store.lastScan.map {
                            "last \($0.formatted(date: .abbreviated, time: .shortened))"
                        } ?? "none yet"
                    ),
                    .init(
                        icon: "sparkles",
                        title: "Cleanups",
                        value: "\(cleanups)",
                        detail: cleanups == 0 ? "none yet" : "recorded across launches"
                    ),
                    .init(
                        icon: "tray.full",
                        title: "Still set aside",
                        value: store.quarantined.isEmpty
                            ? "0 bytes"
                            : store.quarantinedBytes.byteLabel,
                        detail: "waiting in Removed Items",
                        pillText: store.quarantined.isEmpty ? nil : "Can be put back",
                        pillTint: .kivoGood
                    )
                ],
                listTitle: "Cleanup history",
                listRows: store.cleanHistory.reversed().prefix(12).map { event in
                    ActivityRow.Model(
                        icon: "sparkles",
                        title: event.date.formatted(date: .abbreviated, time: .shortened),
                        badge: event.mode == "trash" ? "Trash" : "Removed Items",
                        detail: {
                            let noun = event.removed == 1 ? "item" : "items"
                            let skipped = event.failed > 0
                                ? " · \(event.failed) skipped"
                                : ""
                            return "\(event.removed) \(noun)\(skipped)"
                        }(),
                        value: event.bytes.byteLabel,
                        sortValue: event.bytes
                    )
                }.emptyFallback(
                    .init(
                        icon: "sparkles",
                        title: "No cleanups yet",
                        detail: "Anything you clear will be listed here",
                        value: dash
                    )
                ),
                sideActions: [.overview, .clean, .quarantine]
            )

        }
    }

    // MARK: Shared copy

    private static let diskInfo = """
        Capacity and free space come from the volume itself. Free space is \
        what macOS reports as available for important use, which counts \
        purgeable space such as old snapshots, so it can read higher than \
        Finder's figure.
        """

    private static let cleanableInfo = """
        Caches, logs and the Trash added together. Downloads are measured \
        but left out, because they're your files rather than debris.
        """

    private static let largeFileInfo = """
        Regular files of 1 GB or more in your home folder, 50 biggest kept. \
        The contents of packages such as .app bundles and photo libraries \
        are skipped, so one library counts once instead of flooding the list.
        """

    /// The tiers already describe how free Kivo is with a folder, so the
    /// dot reads straight off them rather than inventing a second scale.
    static func safety(for tier: CleanTier) -> KivoSafety {
        switch tier {
        case .safe: .safe
        case .rebuildable: .check
        case .manual: .keep
        }
    }

    static func tierTint(_ tier: CleanTier) -> Color {
        switch tier {
        case .safe: .kivoGood
        case .rebuildable: .kivoWarn
        case .manual: .kivoDim
        }
    }

    /// Names the other two groups only when there is something in them, so
    /// a Mac with no developer tools doesn't read as if it's hiding space.
    /// Leads with the unused count when there is one, because that is the
    /// number that tells someone what to do next.
    @MainActor
    private static func sublineForApps(_ store: ScanStore) -> String {

        let total = "\(store.appsBytes.byteLabel) in /Applications"

        guard !store.unusedApps.isEmpty else {
            return "\(total). Nothing has gone six months unopened."
        }

        let count = store.unusedApps.count

        return "\(total). \(count) app\(count == 1 ? "" : "s") "
            + "unopened for six months, holding \(store.unusedBytes.byteLabel)."
    }

    @MainActor
    private static func sublineForClean(_ store: ScanStore) -> String {

        var parts: [String] = []

        if store.rebuildableBytes > 0 {
            parts.append("\(store.rebuildableBytes.byteLabel) more can go if you'll re-download it")
        }

        if store.manualBytes > 0 {
            parts.append("\(store.manualBytes.byteLabel) is yours or another tool's to clear")
        }

        return parts.isEmpty
            ? "These folders rebuild themselves."
            : parts.joined(separator: ". ") + "."
    }

    /// Grey until the disk is actually filling up. A capacity bar that is
    /// green at 40% has spent its colour before anything is wrong.
    private static func quietUnlessBusy(_ fraction: Double?) -> Color {
        guard let fraction else { return .kivoDim }
        if fraction > 0.9 { return .kivoRisk }
        if fraction > 0.75 { return .kivoWarn }
        return .kivoDim
    }

    private static func diskTint(_ fraction: Double?) -> Color {
        guard let fraction else { return .kivoDim }
        if fraction > 0.9 { return .kivoRisk }
        if fraction > 0.75 { return .kivoWarn }
        return .kivoGood
    }

    /// "3 mo ago", or a plain statement that macOS has no record. The two
    /// are different claims and the column keeps them apart.
    static func usageLabel(_ app: InstalledApp) -> String {

        guard let used = app.lastUsed else { return "no record" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: used, relativeTo: Date())
    }

    static func usageTint(_ app: InstalledApp) -> Color {
        if app.isUnused() { return .kivoWarn }
        return app.hasUsageRecord ? .kivoDim : .kivoDim.opacity(0.7)
    }

    private static func shortPath(_ url: URL) -> String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Three tiles from a measured list, padded so the row keeps its shape
    /// on a Mac with fewer than three matches.
    private static func tiles(
        from items: [(name: String, size: Int64, url: URL, detail: String?)],
        icon: String,
        detail: String,
        measured: Bool,
        emptyTitle: String
    ) -> [SectionTile] {

        var tiles = items.map { item in
            SectionTile(
                icon: icon,
                fileURL: item.url,
                title: item.name,
                value: item.size.byteLabel,
                detail: item.detail ?? detail
            )
        }

        while tiles.count < 3 {
            tiles.append(
                SectionTile(
                    icon: icon,
                    title: emptyTitle,
                    value: "—",
                    detail: measured ? "none found" : "not measured yet"
                )
            )
        }

        return tiles
    }
}

private extension Array where Element == ActivityRow.Model {

    func emptyFallback(_ row: Element) -> [Element] {
        isEmpty ? [row] : self
    }
}
