//
//  SkyTypography.swift
//  CloudCrown
//

import SwiftUI

enum SkyFont {
    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func headline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }
    static func caption(_ size: CGFloat = 13) -> Font {
        .system(size: max(size, minimumPointSize), weight: .regular, design: .rounded)
    }

    /// Smallest type in the app. The floor is enforced here rather than at each
    /// call site: the codebase asked for 9pt and 10pt in ~95 places, which is
    /// below what is comfortably readable on device.
    static func micro(_ size: CGFloat = 12) -> Font {
        .system(size: max(size, minimumPointSize), weight: .medium, design: .rounded)
    }

    /// No text in the app renders smaller than this.
    static let minimumPointSize: CGFloat = 12
    /// Tabular figures for metric readouts so numbers do not jitter.
    static func metric(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
}

enum SkySpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum SkyRadius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let pill: CGFloat = 999
}
