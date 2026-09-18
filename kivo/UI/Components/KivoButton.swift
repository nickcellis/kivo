//
//  KivoButton.swift
//  kivo
//
//  Created by Thawatchai Chumsook on 18/09/2026.
//

import SwiftUI

// MARK: - Primary

/// Solid blue, small radius, 28pt tall. Flat on purpose — the gradient
/// capsule this replaced read as consumer-app, not as a security utility.
struct KivoButton: View {

    let title: String
    var icon: String?
    var isWide: Bool = false
    var action: () -> Void = {}

    init(
        title: String,
        icon: String? = nil,
        isWide: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.icon = icon
        self.isWide = isWide
        self.action = action
    }

    var body: some View {

        Button(action: action) {

            HStack(spacing: 5) {

                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(title)
            }
            .frame(maxWidth: isWide ? .infinity : nil)
        }
        .buttonStyle(KivoFilledButtonStyle())
    }
}

struct KivoFilledButtonStyle: ButtonStyle {

    var tint: Color = .kivoAccent

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, tint: tint)
    }

    /// Nested view because a `ButtonStyle` can't hold `@State`, and hover is
    /// what makes these read as Mac controls rather than as pictures.
    private struct StyleBody: View {

        let configuration: Configuration
        let tint: Color

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        private var fill: Color {
            if configuration.isPressed { return tint.opacity(0.78) }
            return isHovering ? tint.opacity(0.88) : tint
        }

        var body: some View {

            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(fill)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: KivoMetrics.controlRadius,
                        style: .continuous
                    )
                )
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .onHover { isHovering = $0 }
                .kivoPointerCursor()
        }
    }
}

// MARK: - Secondary

/// Bordered, same 28pt height, for the action beside the primary one.
struct KivoSecondaryButton: View {

    let title: String
    var icon: String?
    var action: () -> Void = {}

    init(
        title: String,
        icon: String? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {

        Button(action: action) {

            HStack(spacing: 5) {

                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(title)
            }
        }
        .buttonStyle(KivoBorderedButtonStyle())
    }
}

struct KivoBorderedButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {

        let configuration: Configuration

        @State private var isHovering = false

        private var shape: RoundedRectangle {
            RoundedRectangle(
                cornerRadius: KivoMetrics.controlRadius,
                style: .continuous
            )
        }

        var body: some View {

            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.kivoAccent)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background {
                    shape.fill(
                        Color.kivoAccent.opacity(
                            configuration.isPressed ? 0.16 : (isHovering ? 0.08 : 0)
                        )
                    )
                }
                .overlay {
                    shape.strokeBorder(
                        Color.kivoAccent.opacity(isHovering ? 0.75 : 0.45),
                        lineWidth: 1
                    )
                }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .onHover { isHovering = $0 }
                .kivoPointerCursor()
        }
    }
}

// MARK: - Destructive

/// Red, for the actions that can't be undone. Figma's own example is a
/// delete button in red: colour is what stops someone reading past it.
struct KivoDestructiveButton: View {

    let title: String
    var icon: String?
    var action: () -> Void = {}

    init(
        title: String,
        icon: String? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {

        Button(action: action) {

            HStack(spacing: 5) {

                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(title)
            }
        }
        .buttonStyle(KivoFilledButtonStyle(tint: .kivoRisk))
    }
}

// MARK: - Quiet

/// Text-only action for a section header ("View details").
struct KivoQuietButton: View {

    let title: String
    var icon: String?

    /// Tints the label red on hover, for a quiet action that still deletes.
    var isDestructive: Bool = false
    var action: () -> Void = {}

    init(
        title: String,
        icon: String? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.icon = icon
        self.isDestructive = isDestructive
        self.action = action
    }

    @State private var isHovering = false

    var body: some View {

        Button(action: action) {

            HStack(spacing: 3) {

                Text(title)

                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(
                isHovering
                    ? (isDestructive ? Color.kivoRisk : Color.kivoAccent)
                    : Color.kivoDim
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .kivoPointerCursor()
    }
}

// MARK: - Icon

/// Toolbar-style icon button. Always carries a VoiceOver label and a tooltip.
struct KivoIconButton: View {

    let systemImage: String
    let label: String
    var action: () -> Void = {}

    @State private var isHovering = false

    var body: some View {

        Button(action: action) {

            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .frame(width: 26, height: 26)
                .background(Color.kivoFill.opacity(isHovering ? 1 : 0))
                .clipShape(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .kivoPointerCursor()
    }
}

#Preview {

    HStack(spacing: 8) {
        KivoButton(title: "Scan Now", icon: "shield.lefthalf.filled")
        KivoSecondaryButton(title: "Custom Scan")
        KivoQuietButton(title: "View details", icon: "chevron.right")
        KivoIconButton(systemImage: "gearshape", label: "Settings")
    }
    .padding(20)
    .background(Color.kivoBackground)
}
