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

/// A light, original Greek-mythic layer used only on the welcome flow.
/// The artwork stays deliberately muted so content remains the priority.
struct OlympusOnboardingBackground: View {
    let step: Int

    private var imageName: String {
        switch step {
        case 0: return "OlympusDawn"
        case 1: return "OlympusTwilight"
        case 2: return "OlympusSunrise"
        default: return "OlympusStorm"
        }
    }

    var body: some View {
        ZStack {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(Color.white.opacity(0.42))
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.22), .clear, .white.opacity(0.30)],
                                   startPoint: .top,
                                   endPoint: .bottom)
                )

            Circle()
                .fill(SkyPalette.lightBlue.opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 75)
                .offset(x: -120, y: -270)
            Circle()
                .fill(SkyPalette.gold.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 120, y: 280)
        }
        .allowsHitTesting(false)
    }
}

/// Ten reusable Olympus accents: five illustrated props and five gold glyphs.
/// Glyphs keep the system light-weight while the focal moments use the bespoke art.
struct OlympusAccent: View {
    enum Kind: CaseIterable {
        case zeus, microphone, podium, hourglass, shield, laurel
        case calendar, lightning, gem, clouds, timer

        var imageName: String? {
            switch self {
            case .zeus: return "OlympusZeus"
            case .microphone: return "OlympusMicrophone"
            case .podium: return "OlympusPodium"
            case .hourglass: return "OlympusHourglass"
            case .shield: return "OlympusShield"
            case .laurel: return "OlympusLaurel"
            default: return nil
            }
        }

        var symbolName: String {
            switch self {
            case .calendar: return "calendar"
            case .lightning: return "bolt.fill"
            case .gem: return "diamond.fill"
            case .clouds: return "cloud.fill"
            case .timer: return "timer"
            default: return "sparkles"
            }
        }
    }

    let kind: Kind
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let imageName = kind.imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: kind.symbolName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(SkyPalette.crownGradient)
                    .shadow(color: SkyPalette.gold.opacity(0.45), radius: 7, y: 3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
