import SwiftUI

// MARK: - Appearance

/// Stored as a raw string so the Settings window and the main window read
/// the same `@AppStorage` key and can't disagree about the current theme.
enum KivoAppearance: String, CaseIterable, Identifiable {

    case system
    case light
    case dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Settings

/// Reached from Kivo ▸ Settings… (⌘,). Declaring a `Settings` scene is what
/// puts that item in the app menu — it isn't something the window owns,
/// which is why removing the toolbar gear didn't need replacing in the UI.
struct SettingsView: View {

    var body: some View {

        TabView {

            GeneralSettings()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AboutSettings()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 430)
    }
}

// MARK: - General

private struct GeneralSettings: View {

    @AppStorage(KivoAppearance.storageKey)
    private var appearance: KivoAppearance = .system

    @StateObject private var store = ScanStore()
    @State private var stored: Int64 = 0

    /// Kivo's own footprint, shown because a tool that writes files should
    /// say how much it has written and offer to stop.
    private var storedLabel: String {
        stored == 0
            ? "Nothing saved yet. Kivo keeps the last scan and a cleanup log so figures survive a quit."
            : "\(stored.byteLabel) in Application Support: the last scan and a capped cleanup log. Removed Items is separate and not cleared by this."
    }

    var body: some View {

        Form {

            Picker("Appearance:", selection: $appearance) {
                ForEach(KivoAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
            .horizontalRadioGroupLayout()

            Divider()
                .padding(.vertical, 4)

            LabeledContent("Saved data:") {

                VStack(alignment: .leading, spacing: 6) {

                    Text(storedLabel)
                        .font(KivoFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Clear Saved Data") {
                        store.clearSavedData()
                        stored = store.storedBytes
                    }
                    .disabled(stored == 0)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 230)
        .onAppear { stored = store.storedBytes }
    }
}

// MARK: - About

private struct AboutSettings: View {

    private var version: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
    }

    var body: some View {

        VStack(spacing: 10) {

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.kivoAccent)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(spacing: 2) {

                Text("Kivo")
                    .font(.system(size: 15, weight: .semibold))

                Text("Version \(version)")
                    .font(KivoFont.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Cleaning and storage tools for your Mac.")
                .font(KivoFont.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(height: 190)
    }
}

#Preview {
    SettingsView()
}
