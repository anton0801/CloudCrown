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
        .system(size: size, weight: .regular, design: .rounded)
    }
    static func micro(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
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
