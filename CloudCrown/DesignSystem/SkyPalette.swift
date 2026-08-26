//
//  SkyPalette.swift
//  CloudCrown
//
//  Celestial premium palette. Every colour used in the app resolves through
//  this type so the visual direction stays consistent across all modules.
//

import SwiftUI

enum SkyPalette {

    // MARK: - Brand core

    /// #006FF9 — primary azure, used for actions and active states.
    /// Deepened from #2F8CFF so it clears 4.5:1 against white both as text
    /// and as a filled button carrying white text.
    static let azure = Color(hex: 0x006FF9)
    /// #73D2FF — light sky. DECORATIVE ONLY: glows, strokes, chart fills.
    /// Never place text on it — white text scores 1.69:1 here.
    static let lightBlue = Color(hex: 0x73D2FF)
    /// #172B69 — deep blue, used for primary text and night layers.
    static let deepBlue = Color(hex: 0x172B69)
    /// #F6FBFF — cloud white, the base surface of the whole app.
    static let cloudWhite = Color(hex: 0xF6FBFF)
    /// #F5C84C — gold, reserved for crown dials and "best" markers.
    static let gold = Color(hex: 0xF5C84C)
    /// #7857FF — electric violet, reserved for explanation and insight layers.
    static let violet = Color(hex: 0x7857FF)

    // MARK: - Semantic

    static let textPrimary = deepBlue
    static let textSecondary = Color(hex: 0x5A6B96)   // 5.28:1 on white
    /// Deepened from #8D9BBD (2.78:1) — the old value was unreadable at the
    /// small sizes it is used at. Now 4.50:1.
    static let textTertiary = Color(hex: 0x6376A5)

    static let surface = Color.white
    static let surfaceSunken = Color(hex: 0xEDF5FE)
    static let canvas = cloudWhite

    static let hairline = Color(hex: 0xDCE8F7)
    static let divider = Color(hex: 0xE6EFFB)

    /// Verdict colours — deliberately distinct from raw metric colours.
    static let verdictBest = Color(hex: 0x13875B)            // 4.52:1
    static let verdictAcceptable = Color(hex: 0x006FF9)      // 4.52:1
    static let verdictNotRecommended = Color(hex: 0xD04921)  // 4.51:1
    static let verdictUnknown = Color(hex: 0x6376A5)         // 4.50:1

    /// Warning / lightning accents.
    static let warning = Color(hex: 0xA06C11)  // 4.52:1 — #E8A020 was 2.22:1
    static let danger = Color(hex: 0xDD372B)   // 4.51:1
    static let success = Color(hex: 0x13875B)  // 4.52:1

    /// Unknown / needs-verification. Never green, never zero-looking.
    static let unknown = Color(hex: 0x6276A3)  // 4.53:1 — #9AA7C4 was 2.41:1

    // MARK: - Gradients

    static var skyCanvasGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: 0xFFFFFF),
                Color(hex: 0xF6FBFF),
                Color(hex: 0xE8F3FF)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Gradient for surfaces that carry white text.
    ///
    /// `azureGradient` starts at #73D2FF, where white text sits at 1.69:1 and
    /// is effectively invisible. Every point of this one clears 4.5:1.
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [azure, deepBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var azureGradient: LinearGradient {
        LinearGradient(
            colors: [lightBlue, azure],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var crownGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                gold,
                Color(hex: 0xFFE9A8),
                gold,
                Color(hex: 0xE0A82F),
                gold
            ]),
            center: .center
        )
    }

    static var violetGradient: LinearGradient {
        LinearGradient(
            colors: [violet, Color(hex: 0xA88BFF)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var nightGradient: LinearGradient {
        LinearGradient(
            colors: [deepBlue, Color(hex: 0x2A4396)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Layered glow used behind celestial cards.
    static func glow(_ color: Color, opacity: Double = 0.35) -> RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
            center: .center,
            startRadius: 0,
            endRadius: 140
        )
    }
}

// MARK: - Hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
