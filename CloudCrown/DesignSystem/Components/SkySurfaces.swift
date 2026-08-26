//
//  SkySurfaces.swift
//  CloudCrown
//
//  Backgrounds and card surfaces. "Glowing celestial layers" are built from
//  soft blurred orbs over a cloud-white canvas — no images, all vector.
//

import SwiftUI

/// The app-wide background: cloud-white canvas with cool drifting glow.
struct SkyBackground: View {
    var intensity: Double = 1.0

    var body: some View {
        ZStack {
            SkyPalette.skyCanvasGradient
                .ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    orb(SkyPalette.lightBlue, 0.30 * intensity, 320)
                        .offset(x: -geo.size.width * 0.32, y: -geo.size.height * 0.18)
                    orb(SkyPalette.azure, 0.16 * intensity, 380)
                        .offset(x: geo.size.width * 0.40, y: -geo.size.height * 0.30)
                    orb(SkyPalette.violet, 0.11 * intensity, 300)
                        .offset(x: geo.size.width * 0.34, y: geo.size.height * 0.34)
                    orb(SkyPalette.gold, 0.09 * intensity, 240)
                        .offset(x: -geo.size.width * 0.30, y: geo.size.height * 0.40)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func orb(_ color: Color, _ opacity: Double, _ size: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: 80)
    }
}

/// A white "cloud surface" card with cool glow shadow.
struct CloudCard<Content: View>: View {
    var padding: CGFloat = SkySpacing.l
    var radius: CGFloat = SkyRadius.large
    var tint: Color = SkyPalette.azure
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(SkyPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(SkyPalette.hairline, lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.10), radius: 18, x: 0, y: 8)
            .shadow(color: SkyPalette.deepBlue.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

/// Elevated card used for the "primary" moment on a screen (next good window).
struct CelestialCard<Content: View>: View {
    /// heroGradient, not azureGradient: this card is always filled with
    /// white text, and azureGradient's light end leaves it at 1.69:1.
    var gradient: LinearGradient = SkyPalette.heroGradient
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(SkySpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: SkyRadius.large, style: .continuous)
                        .fill(gradient)
                    RoundedRectangle(cornerRadius: SkyRadius.large, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: SkyRadius.large, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
            )
            .shadow(color: SkyPalette.azure.opacity(0.30), radius: 22, x: 0, y: 12)
    }
}

/// Section header used across list screens.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SkyFont.headline(16))
                    .foregroundColor(SkyPalette.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textTertiary)
                }
            }
            Spacer(minLength: SkySpacing.s)
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(SkyFont.caption(13).weight(.semibold))
                        .foregroundColor(SkyPalette.azure)
                }
            }
        }
    }
}
