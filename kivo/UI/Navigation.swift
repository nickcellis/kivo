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

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            // A real `List` selection rather than custom buttons: keyboard
            // navigation, the focus ring and the system highlight come with it.
            List(selection: $selectedSection) {

                ForEach(SidebarGroup.allCases) { group in

                    Section {

                        ForEach(group.sections) { section in

                            Label(section.title, systemImage: section.icon)
                                .font(.system(size: 13))
                                .padding(.vertical, 3)
                                .tag(section)
                                .accessibilityHint(section.subtitle)
                        }

                    } header: {

                        // The same uppercase monospace micro-label the cards
                        // use, so the sidebar belongs to the same instrument.
                        Text(group.title.uppercased())
                            .font(KivoFont.label)
                            .tracking(0.8)
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
            .padding(.top, 6)

            SidebarFooter(status: status, volume: volume)
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

    var body: some View {

        VStack(alignment: .leading, spacing: 7) {

            Divider().overlay(Color.kivoBorder)

            VStack(alignment: .leading, spacing: 5) {

                HStack(spacing: 6) {

                    Text(status.shortLabel.uppercased())
                        .font(KivoFont.label)
                        .tracking(0.8)
                        .foregroundStyle(Color.kivoDim)

                    Spacer(minLength: 6)

                    if let volume {
                        Text("\(Int(volume.fraction * 100))%")
                            .font(KivoFont.mono)
                            .foregroundStyle(Color.kivoText)
                    }
                }

                if let volume {

                    KivoProgressBar(
                        fraction: volume.fraction,
                        tint: status.tint,
                        height: 3
                    )

                    Text("\(volume.free.byteLabel) free")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Title bar

/// The app's name in the title bar itself, beside the window buttons.
///
/// It rides in a toolbar rather than a bar of our own: with the title bar
/// hidden, AppKit is what knows where the traffic lights end, so letting it
/// place the item is the only way the alignment stays right across window
/// sizes and system versions.
struct BrandMark: View {

    var body: some View {

        HStack(alignment: .firstTextBaseline, spacing: 6) {

            Text("Kivo")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.kivoText)

            Text("MAC CARE")
                .font(KivoFont.label)
                .tracking(0.9)
                .foregroundStyle(Color.kivoDim)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kivo, Mac Care")
    }
}

/// Our own sidebar toggle, so the order in the title bar is ours to set.
///
/// The one `NavigationSplitView` installs is always placed first, ahead of
/// anything else in the navigation group, which puts the app's name second.
/// Removing it and driving the same AppKit action by hand is the only way
/// to get the brand next to the window buttons.
struct SidebarToggleButton: View {

    var body: some View {

        Button {
            NSApp.keyWindow?.firstResponder?.tryToPerform(
                #selector(NSSplitViewController.toggleSidebar(_:)),
                with: nil
            )
        } label: {
            Image(systemName: "sidebar.leading")
        }
        .help("Hide or show the sidebar")
        .accessibilityLabel("Toggle sidebar")
    }
}
