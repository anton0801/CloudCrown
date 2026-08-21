//
//  Navigation.swift
//  CloudCrown
//
//  Routing helpers for iOS 15 (NavigationStack is unavailable before iOS 16,
//  so pushes are driven by an optional route + a hidden NavigationLink).
//

import SwiftUI

extension View {
    /// Pushes `destination` whenever `route` becomes non-nil.
    func routed<R: Identifiable, D: View>(_ route: Binding<R?>,
                                          @ViewBuilder destination: @escaping (R) -> D) -> some View {
        background(
            NavigationLink(
                isActive: Binding(
                    get: { route.wrappedValue != nil },
                    set: { if !$0 { route.wrappedValue = nil } }
                ),
                destination: {
                    if let value = route.wrappedValue {
                        destination(value)
                    } else {
                        EmptyView()
                    }
                },
                label: { EmptyView() }
            )
            .opacity(0)
            .accessibilityHidden(true)
        )
    }

    /// Applies the shared screen chrome: sky background and cloud-white canvas.
    func skyScreen(title: String? = nil, displayMode: NavigationBarItem.TitleDisplayMode = .large) -> some View {
        background(SkyBackground().ignoresSafeArea())
            .navigationTitle(title ?? "")
            .navigationBarTitleDisplayMode(title == nil ? .inline : displayMode)
    }

    @ViewBuilder
    func applyIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

/// Wraps an id so any UUID can drive `.sheet(item:)` / `routed(_:)`.
struct IdentifiableID: Identifiable, Equatable {
    let id: UUID
}

struct IdentifiableString: Identifiable, Equatable {
    let id: String
}
