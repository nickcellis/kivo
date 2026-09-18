import SwiftUI

/// Asks once, in the app, instead of letting macOS ask three times a scan.
///
/// Desktop, Documents and Downloads each raise their own system prompt the
/// moment something reads them. Kivo skips all three until Full Disk Access
/// is granted, so a scan stays quiet and this card explains what is missing
/// from the results.
struct AccessBanner: View {

    var onGrant: () -> Void = {}

    var body: some View {

        KivoCard(padding: 12, accent: .kivoWarn) {

            HStack(spacing: 10) {

                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.kivoWarn)

                VStack(alignment: .leading, spacing: 2) {

                    Text("Kivo is skipping Desktop, Documents and Downloads")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.kivoText)

                    Text("macOS protects those folders. Turn on Full Disk Access to include them, then reopen Kivo. Scans work without it, they just miss those three.")
                        .font(KivoFont.caption)
                        .foregroundStyle(Color.kivoDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                KivoSecondaryButton(title: "Open Settings", icon: "arrow.up.forward") {
                    onGrant()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
