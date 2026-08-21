//
//  SkyControls.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Buttons

enum SkyButtonStyleKind {
    case primary, secondary, ghost, destructive, gold
}

struct SkyButton: View {
    let title: String
    var icon: String?
    var kind: SkyButtonStyleKind = .primary
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard isEnabled, !isLoading else { return }
            action()
        }) {
            HStack(spacing: SkySpacing.s) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foreground))
                        .scaleEffect(0.8)
                } else if let icon = icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(SkyFont.headline(15))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(foreground)
            .padding(.horizontal, SkySpacing.l)
            .padding(.vertical, 13)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous))
            .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
        }
        .buttonStyle(SkyPressStyle())
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.45)
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary: SkyPalette.azureGradient
        case .gold: LinearGradient(colors: [SkyPalette.gold, Color(hex: 0xE8B33A)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .secondary: SkyPalette.surface
        case .ghost: Color.clear
        case .destructive: SkyPalette.surface
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .gold: return SkyPalette.deepBlue
        case .secondary: return SkyPalette.azure
        case .ghost: return SkyPalette.textSecondary
        case .destructive: return SkyPalette.danger
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary, .gold: return .clear
        case .secondary: return SkyPalette.azure.opacity(0.35)
        case .ghost: return SkyPalette.hairline
        case .destructive: return SkyPalette.danger.opacity(0.35)
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .primary: return SkyPalette.azure.opacity(0.28)
        case .gold: return SkyPalette.gold.opacity(0.30)
        default: return .clear
        }
    }
}

struct SkyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Chips

struct SkyChip: View {
    let title: String
    var icon: String?
    var color: Color = SkyPalette.azure
    var isSelected: Bool = false
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: 5) {
            if let icon = icon {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            }
            Text(title).font(SkyFont.micro(12))
        }
        .foregroundColor(isSelected ? .white : color)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.12)))
        )
        .overlay(
            Capsule().strokeBorder(color.opacity(isSelected ? 0 : 0.22), lineWidth: 1)
        )

        if let action = action {
            Button(action: action) { content }.buttonStyle(SkyPressStyle())
        } else {
            content
        }
    }
}

/// Horizontal wrapping chip row (iOS 15 has no Layout protocol, so this is manual).
struct SkyWrapRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var spacing: CGFloat = SkySpacing.s
    @ViewBuilder let content: (Item) -> Content

    @State private var totalHeight: CGFloat = 0

    var body: some View {
        VStack {
            GeometryReader { geo in
                self.generate(in: geo)
            }
        }
        .frame(height: totalHeight)
    }

    private func generate(in geo: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0
        return ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geo.size.width {
                            width = 0
                            height -= d.height + spacing
                        }
                        let result = width
                        if item.id == items.last?.id { width = 0 } else { width -= d.width + spacing }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item.id == items.last?.id { height = 0 }
                        return result
                    }
            }
        }
        .background(heightReader($totalHeight))
    }

    private func heightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo -> Color in
            DispatchQueue.main.async { binding.wrappedValue = geo.frame(in: .local).size.height }
            return .clear
        }
    }
}

// MARK: - Segmented selector

struct SkySegmented<T: Hashable>: View {
    let options: [T]
    let titleFor: (T) -> String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = option }
                } label: {
                    Text(titleFor(option))
                        .font(SkyFont.micro(12).weight(.semibold))
                        .foregroundColor(selection == option ? .white : SkyPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                .fill(selection == option ? AnyShapeStyle(SkyPalette.azureGradient) : AnyShapeStyle(Color.clear))
                        )
                }
                .buttonStyle(SkyPressStyle())
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(SkyPalette.surfaceSunken)
        )
    }
}

// MARK: - Toolbar-safe close button

struct SkyCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(SkyPalette.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(SkyPalette.surfaceSunken))
        }
    }
}
