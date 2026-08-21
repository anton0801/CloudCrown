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

    /// #2F8CFF — primary azure, used for actions and active states.
    static let azure = Color(hex: 0x2F8CFF)
    /// #73D2FF — light sky, used for glows and secondary accents.
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
    static let textSecondary = Color(hex: 0x5A6B96)
    static let textTertiary = Color(hex: 0x8D9BBD)

    static let surface = Color.white
    static let surfaceSunken = Color(hex: 0xEDF5FE)
    static let canvas = cloudWhite

    static let hairline = Color(hex: 0xDCE8F7)
    static let divider = Color(hex: 0xE6EFFB)

    /// Verdict colours — deliberately distinct from raw metric colours.
    static let verdictBest = Color(hex: 0x18A971)
    static let verdictAcceptable = Color(hex: 0x2F8CFF)
    static let verdictNotRecommended = Color(hex: 0xE0623D)
    static let verdictUnknown = Color(hex: 0x8D9BBD)

    /// Warning / lightning accents.
    static let warning = Color(hex: 0xE8A020)
    static let danger = Color(hex: 0xE0483D)
    static let success = Color(hex: 0x18A971)

    /// Unknown / needs-verification. Never green, never zero-looking.
    static let unknown = Color(hex: 0x9AA7C4)

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
