import SwiftUI
import AppKit

// MARK: - Sections

enum SidebarSection: String, CaseIterable, Identifiable {

    case overview
    case clean
    case leftovers
    case duplicates
    case applications
    case storage
    case largeFiles
    case diskMap
    case quarantine
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Dashboard"
        case .clean: "Clean"
        case .leftovers: "Leftovers"
        case .duplicates: "Duplicates"
        case .applications: "Applications"
        case .storage: "Storage"
        case .largeFiles: "Large Files"
        case .diskMap: "Disk Map"
        case .quarantine: "Removed Items"
        case .activity: "Activity"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .clean: "sparkles"
        case .leftovers: "shippingbox"
        case .duplicates: "doc.on.doc"
        case .applications: "square.stack.3d.up"
        case .storage: "internaldrive"
        case .largeFiles: "doc"
        case .diskMap: "square.grid.3x3.topleft.filled"
        case .quarantine: "tray.full"
        case .activity: "clock.arrow.circlepath"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "What's on this Mac and what can go."
        case .clean: "Files your Mac can rebuild by itself."
        case .leftovers: "Support files from apps you no longer have."
        case .duplicates: "The same file kept in more than one place."
        case .applications: "What's installed, and how big each app is."
        case .storage: "How the startup disk is filled."
        case .largeFiles: "Files of 1 GB or more in your home folder."
        case .diskMap: "Every folder drawn to scale."
        case .quarantine: "Things Kivo took away. Put any of them back."
        case .activity: "What Kivo has done on this Mac."
        }
    }
}

// MARK: - Groups

/// The nav as data rather than six hand-written rows.
enum SidebarGroup: String, CaseIterable, Identifiable {

    case main
    case cleanup
    case storage
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: "Main"
        case .cleanup: "Cleanup"
        case .storage: "Storage"
        case .other: "Other"
        }
    }

    var sections: [SidebarSection] {
        switch self {
        case .main: [.overview]
        case .cleanup: [.clean, .leftovers, .duplicates, .applications]
        case .storage: [.storage, .largeFiles, .diskMap]
        case .other: [.quarantine, .activity]
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {

    @Binding var selectedSection: SidebarSection
    var status: KivoStatus = .good
    var volume: VolumeInfo?
    var held: Int64 = 0

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            // A real `List` selection rather than custom buttons: keyboard
            // navigation, the focus ring and the system highlight come with it.
            List(selection: $selectedSection) {

                ForEach(SidebarGroup.allCases) { group in

                    Section {

                        ForEach(group.sections) { section in

                            Label {
                                Text(section.title)
                                    .font(.system(size: 13))
                            } icon: {
                                Image(systemName: section.icon)
                                    // Colour on the selected icon alone.
                                    // An accent used everywhere stops being
                                    // an accent and becomes a background.
                                    .foregroundStyle(
                                        selectedSection == section
                                            ? Color.kivoAccent
                                            : Color.kivoDim
                                    )
                            }
                            .padding(.vertical, 4)
                            .tag(section)
                            .accessibilityHint(section.subtitle)
                        }

                    } header: {

                        // The same uppercase monospace micro-label the cards
                        // use, so the sidebar belongs to the same instrument.
                        Text(group.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.kivoDim)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            // Roomier than the tables: this is the one list you read by
            // shape rather than by scanning down a column of figures, and
            // it lost its header when the brand moved to the title bar.
            .environment(\.defaultMinListRowHeight, 32)
            // Clears the window buttons, which now float over the sidebar.
            .padding(.top, 30)

            SidebarFooter(status: status, volume: volume, held: held)
        }
        .background(Color.kivoSidebar)
    }
}

// MARK: - Footer

/// Disk state, always visible. It's the context for everything in the app,
/// so it belongs somewhere that doesn't change with the selected screen.
private struct SidebarFooter: View {

    let status: KivoStatus
    let volume: VolumeInfo?
    var held: Int64 = 0

    var body: some View {

        VStack(alignment: .leading, spacing: 7) {

            Divider().overlay(Color.kivoBorder)

            VStack(alignment: .leading, spacing: 5) {

                // Name the thing, then say how full it is. This line used
                // to read "Clear" beside "73%", because the left half was
                // a health verdict and the right half was the fill — so a
                // disk that is 73% full announced itself as 73% clear.
                // The health is in the colour of the figure and the bar
                // under it, which is where a one-word verdict belongs.
                // One phrase, not two halves shoved to opposite edges.
                // With a Spacer between them the line stretched the full
                // width of the column and made it feel packed, which is
                // the opposite of what a quiet footer should do.
                HStack(spacing: 6) {

                    Text("Startup disk")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.kivoDim)

                    if let volume {
                        Text("\(Int(volume.fraction * 100))% full")
                            .font(KivoFont.mono)
                            .foregroundStyle(
                                status == .good ? Color.kivoText : status.tint
                            )
                    }

                    Spacer(minLength: 0)
                }

                if let volume {

                    KivoProgressBar(fraction: volume.fraction, height: 3)

                    Text("\(volume.free.byteLabel) free")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)
                }

                // Quarantine is the one thing here that only grows, so its
                // size belongs somewhere always visible rather than on the
                // screen you have to remember to open.
                if held > 0 {

                    Text("\(held.byteLabel) set aside")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoWarn)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .accessibilityElement(children: .combine)
    }
}
