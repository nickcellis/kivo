import SwiftUI
import AppKit

struct ContentView: View {

    @State private var selectedSection: SidebarSection = .overview
    @StateObject private var store = ScanStore()

    @AppStorage(KivoAppearance.storageKey)
    private var appearance: KivoAppearance = .system

    /// Derived from what was measured, never set by hand.
    private var status: KivoStatus {
        guard let fraction = store.volume?.fraction else { return .good }
        if fraction > 0.9 { return .risk }
        if fraction > 0.75 { return .attention }
        return .good
    }

    var body: some View {

        NavigationSplitView {

            Sidebar(
                selectedSection: $selectedSection,
                status: status,
                volume: store.volume,
                held: store.quarantinedBytes
            )
            // The window has no toolbar at all now, so the toggle it would
            // otherwise install has nowhere to belong.
            .toolbar(removing: .sidebarToggle)
            // Outermost: the column width has to be the last thing applied
            // to the sidebar view, or a modifier wrapping it swallows the
            // preference and the column falls back to AppKit's minimum.
            .navigationSplitViewColumnWidth(
                min: KivoMetrics.sidebarWidth,
                ideal: KivoMetrics.sidebarWidth,
                max: 320
            )

        } detail: {

            PageView(
                section: selectedSection,
                status: status,
                store: store,
                onOpen: open
            )
            .id(selectedSection)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.14), value: selectedSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kivoBackground)
        }
        .navigationSplitViewStyle(.balanced)
        // Each column paints its own colour to the very top. Without this
        // SwiftUI lays out 28pt below the title bar and macOS's grey window
        // background shows through the gap, across both columns at once, so
        // it can't match either of them.
        .ignoresSafeArea(.container, edges: .top)
        // Empty rather than absent: with no title set at all, macOS falls
        // back to the app name and puts "kivo" back in the bar.
        .navigationTitle("")
        .tint(Color.kivoAccent)
        .frame(
            minWidth: 900,
            idealWidth: 1000,
            minHeight: 560,
            idealHeight: 660
        )
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            #if DEBUG
            // Screenshots, and only when the environment asks: see
            // DemoMode. It has to come before restore() and instead of
            // it, or the saved scan lands on top of the demo data and the
            // picture is of a real disk. That is exactly what the first
            // attempt published.
            if let demo = DemoMode.section {
                store.loadDemo()
                selectedSection = demo
                DemoMode.captureWhenReady()
                return
            }
            #endif

            store.restore()
        }
    }

    private func open(_ section: SidebarSection) {
        withAnimation(.easeInOut(duration: 0.14)) {
            selectedSection = section
        }
    }
}

// MARK: - Page

/// Hero + disk, a row of metrics, then a table. Every screen is this,
/// filled from `SectionPageConfig`.
struct PageView: View {

    let section: SidebarSection
    var status: KivoStatus = .good
    @ObservedObject var store: ScanStore
    var onOpen: (SidebarSection) -> Void = { _ in }

    @State private var uninstalling: InstalledApp?

    /// The disk figure is the subject of these two pages and background
    /// noise on the other eight.
    private var showsDisk: Bool {
        section == .overview || section == .storage
    }

    private var config: SectionPageConfig {
        .config(for: section, store: store) { app in
            uninstalling = app
        }
    }

    /// Names the screen and states when the figures were taken — without it
    /// the page opens straight into numbers with no idea how old they are.
    /// Reads the clock rather than saying "Dashboard" twice: the sidebar
    /// already names the screen, so the page can open with something a
    /// person would say.
    private var greeting: String {

        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    /// Title, then what the page is, then when it was measured.
    ///
    /// This used to be two rows: an eyebrow naming the section and, under
    /// it, a heading naming the section again. Every page but the
    /// dashboard opened by saying its own name twice.
    private var header: some View {

        HStack(alignment: .lastTextBaseline, spacing: 12) {

            VStack(alignment: .leading, spacing: 3) {

                Text(section == .overview ? greeting : section.title)
                    .font(KivoFont.pageTitle)
                    .foregroundStyle(Color.kivoText)

                Text(section.subtitle)
                    .font(KivoFont.body)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            headerStamp
        }
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }

    private var headerStamp: some View {

        HStack(spacing: 6) {

            if store.isStale {
                KivoStatusPill(text: "Out of date", tint: .kivoWarn)
            }

            Text(lastScanLabel)
                .font(KivoFont.mono)
                .foregroundStyle(Color.kivoDim)
                .lineLimit(1)
        }
    }

    /// Figures restored from a previous launch need their date, not just a
    /// time: "09:41" on a reading taken last week is a lie of omission.
    private var lastScanLabel: String {

        guard let date = store.lastScan else { return "Never scanned" }

        let today = Calendar.current.isDateInToday(date)

        let stamp = today
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)

        return "Scanned \(stamp)"
    }

    var body: some View {

        if section == .diskMap {
            DiskMapView()
        } else if section == .quarantine {
            QuarantineView(store: store)
        } else {
            standardPage
        }
    }

    private var standardPage: some View {

        GeometryReader { proxy in

            ScrollView {

                VStack(spacing: KivoMetrics.sectionSpacing) {

                    header
                        .padding(.top, 14)

                    if !store.hasFullDisk {

                        AccessBanner(
                            onGrant: { DiskAccess.openSettings() }
                        )
                    }

                    if store.showsCleanResult, let result = store.lastClean {

                        ResultBanner(
                            result: result,
                            mode: store.lastCleanMode,
                            onOpenQuarantine: { onOpen(.quarantine) },
                            onDismiss: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    store.showsCleanResult = false
                                }
                            }
                        )
                    }

                    HStack(alignment: .top, spacing: KivoMetrics.gridSpacing) {

                        HeroCard(
                            config: config,
                            status: status,
                            store: store,
                            matchesDisk: showsDisk,
                            onOpen: onOpen
                        )

                        // Only where the disk is the subject. It used to
                        // ride along on all ten pages, repeating the free
                        // space, the percentage and the capacity that the
                        // sidebar already shows at all times.
                        if showsDisk {

                            DiskCard(store: store)
                                .frame(width: 236)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    // A page is allowed to have none: an empty row still
                    // costs a gap in the stack, which reads as something
                    // failing to load.
                    if !config.tiles.isEmpty {

                        HStack(alignment: .top, spacing: KivoMetrics.gridSpacing) {

                            ForEach(config.tiles) { tile in
                                MetricCard(tile: tile)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    // Takes the slack instead of a trailing spacer, so a tall
                    // window grows the list rather than the empty space under it.
                    DataTable(
                        title: config.listTitle,
                        rows: config.listRows
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(KivoMetrics.pagePadding)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
        .sheet(item: $uninstalling) { app in
            UninstallSheet(app: app, store: store)
        }
    }
}

// MARK: - Hero

struct HeroCard: View {

    let config: SectionPageConfig
    let status: KivoStatus
    @ObservedObject var store: ScanStore

    /// Stretch to the disk card's height when there is one beside it, and
    /// otherwise hug the content. Without this the hero kept the height it
    /// needed back when it carried a breakdown strip, and pages that no
    /// longer have one opened with a tall empty box.
    var matchesDisk: Bool = false

    var onOpen: (SidebarSection) -> Void = { _ in }

    @State private var showClean = false
    @State private var showReview = false
    @State private var showDuplicates = false
    @State private var showLargeFiles = false

    private var isScanning: Bool { store.phase.isScanning }

    private var measure: (value: String, unit: String?) {
        kivoSplitMeasure(config.metricValue)
    }

    var body: some View {

        KivoCard(
            padding: 14,
            accent: isScanning ? .kivoAccent : nil,
            fillsHeight: matchesDisk
        ) {

            VStack(alignment: .leading, spacing: 10) {

                if isScanning {

                    scanningPanel

                } else {

                    // Only when it isn't good news. "ALL CLEAR" on every
                    // page of a healthy Mac is a pill the eye stops
                    // reading, which is the whole argument against it.
                    KivoCardLabel(
                        text: config.metricLabel,
                        trailing: status == .good ? nil : status.label,
                        trailingTint: status.tint,
                        info: config.info
                    )

                    KivoMetric(value: measure.value, unit: measure.unit)

                    Text(headline)
                        .font(KivoFont.body)
                        .foregroundStyle(Color.kivoDim)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.isCleaning {
                        KivoProgressBar(fraction: store.cleanProgress, height: 3)
                            .padding(.top, 2)
                    }
                }

                HStack(spacing: 7) {

                    if isScanning {
                        KivoSecondaryButton(title: "Stop") { store.cancel() }
                    } else {
                        KivoButton(
                            title: config.primaryTitle,
                            icon: config.primaryIcon
                        ) {
                            if let destination = config.primaryOpens {
                                onOpen(destination)
                            } else {
                                store.scan(config.scanScopes)
                            }
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        .help("Scan this Mac (⌘R)")

                        if config.offersReview {

                            KivoSecondaryButton(
                                title: "Review",
                                icon: "checklist"
                            ) {
                                showReview = true
                            }
                        }

                        if config.offersDuplicates {

                            KivoSecondaryButton(
                                title: "Review",
                                icon: "checklist"
                            ) {
                                showDuplicates = true
                            }
                        }

                        if config.offersLargeFiles {

                            KivoSecondaryButton(
                                title: "Review",
                                icon: "checklist"
                            ) {
                                showLargeFiles = true
                            }
                        }

                        if config.offersClean {

                            KivoSecondaryButton(
                                title: "Clean",
                                icon: "sparkles"
                            ) {
                                showClean = true
                            }
                            .disabled(!store.has(.cleanable) || store.cleanableBytes == 0)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 2)

                // The breakdown that used to sit here, under a divider,
                // is the row of cards below the hero: on Storage and
                // Activity it was the same three figures twice, a few
                // millimetres apart in two different type sizes.
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(config.headline)
        .sheet(isPresented: $showClean) {
            CleanSheet(store: store)
        }
        .sheet(isPresented: $showReview) {
            OrphanSheet(store: store)
        }
        .sheet(isPresented: $showDuplicates) {
            DuplicateSheet(store: store)
        }
        .sheet(isPresented: $showLargeFiles) {
            LargeFileSheet(store: store)
        }
    }

    /// The step being run, named, counted and sized to be read from across
    /// the desk. A bar on its own says something is happening; it doesn't
    /// say what, or how much is left.
    private var scanningPanel: some View {

        VStack(alignment: .leading, spacing: 10) {

            KivoCardLabel(
                text: "Scanning",
                trailing: "\(store.stepsDone) of \(store.steps.count)",
                trailingTint: .kivoAccent
            )

            HStack(spacing: 9) {

                ProgressView()
                    .controlSize(.small)

                Text(store.currentStep?.title ?? "Working")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.kivoText)
                    .lineLimit(1)
            }

            KivoProgressBar(fraction: store.phase.progress, height: 4)

            Text("Kivo is reading only. A scan moves and removes nothing.")
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)

            stepList
        }
    }

    /// Two columns, so a nine step scan stays about five rows tall.
    private var stepList: some View {

        LazyVGrid(
            columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ],
            alignment: .leading,
            spacing: 5
        ) {

            ForEach(store.steps) { step in

                HStack(spacing: 6) {

                    Group {
                        switch step.state {
                        case .done:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.kivoGood)
                        case .running:
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Color.kivoAccent)
                        case .pending:
                            Image(systemName: "circle")
                                .foregroundStyle(Color.kivoDim.opacity(0.5))
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12)

                    Text(step.title)
                        .font(KivoFont.caption)
                        .foregroundStyle(
                            step.state == .pending ? Color.kivoDim : Color.kivoText
                        )
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.title), \(stateLabel(step.state))")
            }
        }
        .padding(.top, 2)
        .animation(.easeOut(duration: 0.2), value: store.steps)
    }

    private func stateLabel(_ state: ScanStep.State) -> String {
        switch state {
        case .done: "done"
        case .running: "in progress"
        case .pending: "waiting"
        }
    }

    private var headline: String {
        if store.isCleaning {
            return "Moving files to the Trash."
        }
        if case .scanning(_, let label) = store.phase {
            return "\(label). Kivo is reading only, and removes nothing."
        }
        return config.subline
    }

}

// MARK: - Disk

/// The volume, broken into what's used, what Kivo could clear and what
/// the disk holds. On the dashboard and the Storage page only: everywhere
/// else the sidebar's own free-space line is the context, and this card
/// repeated it.
struct DiskCard: View {

    @ObservedObject var store: ScanStore

    private var volume: VolumeInfo? { store.volume }

    private var tint: Color {
        guard let fraction = volume?.fraction else { return .kivoDim }
        if fraction > 0.9 { return .kivoRisk }
        if fraction > 0.75 { return .kivoWarn }
        return .kivoDim
    }

    var body: some View {

        KivoCard(padding: 14, fillsHeight: true) {

            VStack(alignment: .leading, spacing: 10) {

                KivoCardLabel(
                    text: "Disk",
                    trailing: volume.map { "\(Int($0.fraction * 100))% full" },
                    trailingTint: tint,
                    info: """
                        Free space is what macOS reports as available for \
                        important use. That counts purgeable space such as \
                        old snapshots, so it can read higher than Finder's \
                        figure. The amber part of the bar is what Kivo has \
                        measured as cleanable.
                        """
                )

                let free = kivoSplitMeasure(volume?.free.byteLabel ?? "—")

                KivoMetric(value: free.value, unit: free.unit.map { "\($0) free" })

                KivoSegmentBar(
                    segments: segments,
                    height: 6
                )

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: 3) {

                    row(
                        "Used",
                        volume?.used.byteLabel ?? "—",
                        dot: tint
                    )

                    row(
                        "Cleanable",
                        store.has(.cleanable) ? store.cleanableBytes.byteLabel : "—",
                        dot: .kivoWarn
                    )

                    row(
                        "Capacity",
                        volume?.total.byteLabel ?? "—",
                        dot: .kivoDim
                    )
                }
            }
        }
    }

    private var segments: [KivoSegmentBar.Segment] {

        guard let volume, volume.total > 0 else { return [] }

        let cleanable = store.has(.cleanable)
            ? Double(store.cleanableBytes) / Double(volume.total)
            : 0

        let used = max(volume.fraction - cleanable, 0)

        return [
            .init(fraction: used, tint: tint),
            .init(fraction: cleanable, tint: .kivoWarn)
        ]
    }

    private func row(_ title: String, _ value: String, dot: Color) -> some View {

        HStack(spacing: 6) {

            Circle().fill(dot).frame(width: 4, height: 4)

            Text(title)
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)

            Spacer(minLength: 8)

            Text(value)
                .font(KivoFont.mono)
                .foregroundStyle(Color.kivoText)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Metric card

struct MetricCard: View {

    let tile: SectionTile

    var body: some View {

        KivoCard(padding: 14, fillsHeight: true) {

            VStack(alignment: .leading, spacing: 9) {

                HStack(spacing: 7) {

                    if let fileURL = tile.fileURL {
                        Image(nsImage: AppIcons.icon(for: fileURL))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                    }

                    KivoCardLabel(
                        text: tile.title,
                        trailing: tile.pillText,
                        trailingTint: tile.pillTint,
                        info: tile.info
                    )
                }

                let measure = kivoSplitMeasure(tile.value)

                KivoMetric(value: measure.value, unit: measure.unit, small: true)

                Text(tile.detail)
                    .font(KivoFont.caption)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)

                if let fraction = tile.fraction {
                    KivoProgressBar(fraction: fraction, tint: tile.barTint, height: 3)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Finder actions

private struct FileContextMenu: ViewModifier {

    let url: URL?

    func body(content: Content) -> some View {

        if let url {

            content.contextMenu {

                Button("Show in Finder") { FileActions.reveal(url) }
                Button("Open") { FileActions.open(url) }
                Divider()
                Button("Copy Path") { FileActions.copyPath(url) }
            }

        } else {
            content
        }
    }
}

extension View {

    /// Right click anything that stands for a real file.
    func kivoFileMenu(_ url: URL?) -> some View {
        modifier(FileContextMenu(url: url))
    }
}

// MARK: - Table

/// Dense monospace rows. Values are right-aligned in a fixed column so
/// sizes compare down the page rather than wandering with the name length.
/// How the table is ordered. Starts as given, because the pages hand their
/// rows over already ranked by whatever matters there, usually size.
enum RowSort: Equatable {

    case given
    case name(ascending: Bool)
    case used(ascending: Bool)
    case size(ascending: Bool)
}

/// Dense monospace rows, sortable by either column. Values are right
/// aligned in a fixed column so sizes compare down the page rather than
/// wandering with the length of the name beside them.
struct DataTable: View {

    let title: String
    let rows: [ActivityRow.Model]

    @State private var sort: RowSort = .given

    private var sorted: [ActivityRow.Model] {

        switch sort {

        case .given:
            return rows

        case .name(let ascending):
            return rows.sorted {
                ascending
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.title.localizedStandardCompare($1.title) == .orderedDescending
            }

        case .size(let ascending):
            return rows.sorted {
                // Rows with no size behind them are placeholders, and sit
                // at the bottom whichever way the column is pointing.
                let left = $0.sortValue ?? -1
                let right = $1.sortValue ?? -1
                return ascending ? left < right : left > right
            }

        case .used(let ascending):
            return rows.sorted {
                // No record sorts last either way, rather than pretending
                // to be the oldest date on the list.
                guard let left = $0.sortDate else { return false }
                guard let right = $1.sortDate else { return true }
                return ascending ? left < right : left > right
            }
        }
    }

    /// Only worth offering when the rows actually carry sizes.
    private var canSort: Bool {
        rows.contains { $0.sortValue != nil } && rows.count > 1
    }

    private var hasSecondary: Bool {
        rows.contains { $0.secondary != nil }
    }

    var body: some View {

        KivoCard(padding: 0) {

            VStack(spacing: 0) {

                HStack(spacing: 8) {

                    header(title, field: .name(ascending: true))

                    Spacer(minLength: 8)

                    if hasSecondary {
                        header("Opened", field: .used(ascending: false))
                            .frame(width: 92, alignment: .trailing)
                    }

                    header("Size", field: .size(ascending: false))
                        .frame(width: 88, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                Divider().overlay(Color.kivoBorder)

                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, row in

                    if index > 0 {
                        Divider().overlay(Color.kivoBorder).padding(.leading, 12)
                    }

                    ActivityRow(model: row)
                }
            }
        }
    }

    @ViewBuilder
    private func header(_ text: String, field: RowSort) -> some View {

        if canSort {

            Button {
                toggle(field)
            } label: {
                HStack(spacing: 3) {

                    Text(text)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isActive(field) ? Color.kivoText : Color.kivoDim)

                    if let ascending = direction(field) {
                        Image(systemName: ascending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.kivoAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .kivoPointerCursor()
            .help("Sort by \(text.lowercased())")

        } else {

            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.kivoDim)
        }
    }

    /// Clicking the active column flips it; clicking the other one starts
    /// it at the direction that reads naturally: names up, sizes down.
    private func toggle(_ field: RowSort) {

        switch (sort, field) {
        case (.name(let ascending), .name):
            sort = .name(ascending: !ascending)
        case (.size(let ascending), .size):
            sort = .size(ascending: !ascending)
        case (.used(let ascending), .used):
            sort = .used(ascending: !ascending)
        default:
            sort = field
        }
    }

    private func isActive(_ field: RowSort) -> Bool {
        direction(field) != nil
    }

    private func direction(_ field: RowSort) -> Bool? {

        switch (sort, field) {
        case (.name(let ascending), .name): ascending
        case (.size(let ascending), .size): ascending
        case (.used(let ascending), .used): ascending
        default: nil
        }
    }
}

struct ActivityRow: View {

    /// Property order is the memberwise initialiser's argument order, so
    /// it follows how a row reads: what it is, then what it says, then the
    /// number, then the machinery behind the number.
    struct Model: Identifiable {

        let id = UUID()
        let icon: String

        /// The file this row stands for: its icon, what Finder reveals,
        /// and what opening acts on.
        var fileURL: URL?

        let title: String

        /// Sits right after the title in monospace, for a version number.
        var badge: String?

        let detail: String
        let value: String

        /// Raw bytes behind `value`, so the size column sorts numerically.
        /// Sorting the formatted string puts "9 KB" after "10 MB".
        var sortValue: Int64?

        /// Green, amber or red at the start of the row, saying how safe
        /// this one is to remove.
        var safety: KivoSafety?

        /// Middle column, shown only on tables whose rows have one.
        var secondary: String?
        var secondaryTint: Color?
        var sortDate: Date?

        /// Makes the row a button. Set on the Applications list so a row
        /// opens the uninstaller for that app.
        var onSelect: (() -> Void)?
    }

    let model: Model

    @State private var isHovering = false

    var body: some View {

        HStack(spacing: 9) {

            if let safety = model.safety {
                KivoSafetyDot(safety: safety)
            }

            if let fileURL = model.fileURL {
                Image(nsImage: AppIcons.icon(for: fileURL))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }

            Text(model.title)
                .font(KivoFont.body)
                .foregroundStyle(Color.kivoText)
                .lineLimit(1)

            if let badge = model.badge {
                Text(badge)
                    .font(KivoFont.mono)
                    .foregroundStyle(Color.kivoDim)
                    .lineLimit(1)
            }

            Text(model.detail)
                .font(KivoFont.caption)
                .foregroundStyle(Color.kivoDim)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if let secondary = model.secondary {
                Text(secondary)
                    .font(KivoFont.mono)
                    .foregroundStyle(model.secondaryTint ?? Color.kivoDim)
                    .lineLimit(1)
                    .frame(width: 92, alignment: .trailing)
            }

            Text(model.value)
                .font(KivoFont.mono)
                .foregroundStyle(Color.kivoText)
                .frame(width: 88, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isHovering && model.onSelect != nil ? Color.kivoFill : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.onSelect?() }
        .kivoFileMenu(model.fileURL)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(model.onSelect == nil ? [] : .isButton)
    }
}

#Preview {
    ContentView()
}
