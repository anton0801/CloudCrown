//
//  CrownDial.swift
//  CloudCrown
//
//  Circular selector shaped like a golden crown: a ring of tapered "points"
//  with a draggable golden arc. Used for every threshold in Comfort Profile
//  and for duration/weight selection.
//

import SwiftUI

struct CrownDial: View {
    let title: String
    var unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var tint: Color = SkyPalette.gold
    /// When nil the dial renders in "Not set / Unknown" state instead of showing a number.
    var isSet: Bool = true
    var onChanged: ((Double) -> Void)?

    private let dialSize: CGFloat = 168
    private let lineWidth: CGFloat = 14
    /// Gap at the bottom of the ring, in fraction of a full turn.
    private let gap: Double = 0.22

    @State private var isDragging = false

    private var progress: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(spacing: SkySpacing.m) {
            ZStack {
                crownPoints
                track
                if isSet { arc }
                knob
                centerLabel
            }
            .frame(width: dialSize, height: dialSize)
            .contentShape(Circle())
            .gesture(dragGesture)

            Text(title)
                .font(SkyFont.caption(13))
                .foregroundColor(SkyPalette.textSecondary)
        }
    }

    // MARK: - Layers

    /// Tapered points radiating outward — the "crown" silhouette.
    private var crownPoints: some View {
        ZStack {
            ForEach(0..<24, id: \.self) { i in
                let t = Double(i) / 24.0
                let isMajor = i % 3 == 0
                let angle = (gap / 2 + t * (1 - gap)) * 360 + 90
                Capsule()
                    .fill(
                        pointIsActive(t)
                            ? AnyShapeStyle(tint.opacity(isMajor ? 0.95 : 0.55))
                            : AnyShapeStyle(SkyPalette.hairline)
                    )
                    .frame(width: isMajor ? 3 : 2, height: isMajor ? 11 : 6)
                    .offset(y: -(dialSize / 2 - 2))
                    .rotationEffect(.degrees(angle))
            }
        }
        .animation(.easeOut(duration: 0.18), value: value)
    }

    private func pointIsActive(_ t: Double) -> Bool {
        isSet && t <= progress + 0.0001
    }

    private var track: some View {
        Circle()
            .trim(from: 0, to: CGFloat(1 - gap))
            .stroke(SkyPalette.surfaceSunken, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(90 + gap / 2 * 360))
            .frame(width: dialSize - 34, height: dialSize - 34)
    }

    private var arc: some View {
        Circle()
            .trim(from: 0, to: CGFloat(max(0.001, progress) * (1 - gap)))
            .stroke(SkyPalette.crownGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(90 + gap / 2 * 360))
            .frame(width: dialSize - 34, height: dialSize - 34)
            .shadow(color: tint.opacity(0.45), radius: isDragging ? 14 : 8)
            .animation(.easeOut(duration: 0.18), value: value)
    }

    private var knob: some View {
        Circle()
            .fill(Color.white)
            .frame(width: lineWidth + 8, height: lineWidth + 8)
            .overlay(Circle().strokeBorder(tint, lineWidth: 3))
            .shadow(color: tint.opacity(0.5), radius: 6, y: 2)
            .offset(y: -(dialSize - 34) / 2)
            .rotationEffect(.degrees(knobAngle))
            .opacity(isSet ? 1 : 0)
            .scaleEffect(isDragging ? 1.12 : 1)
            .animation(.easeOut(duration: 0.18), value: value)
            .animation(.easeOut(duration: 0.15), value: isDragging)
    }

    private var knobAngle: Double {
        (gap / 2 + progress * (1 - gap)) * 360 + 180
    }

    private var centerLabel: some View {
        VStack(spacing: 0) {
            if isSet {
                Text(formatted)
                    .font(SkyFont.metric(34))
                    .foregroundColor(SkyPalette.textPrimary)
                Text(unit)
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textTertiary)
            } else {
                Text("Not set")
                    .font(SkyFont.headline(15))
                    .foregroundColor(SkyPalette.unknown)
                Text("tap to define")
                    .font(SkyFont.micro(10))
                    .foregroundColor(SkyPalette.textTertiary)
            }
        }
    }

    private var formatted: String {
        step < 1 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }

    // MARK: - Interaction

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                isDragging = true
                update(from: g.location)
            }
            .onEnded { _ in
                isDragging = false
                onChanged?(value)
            }
    }

    private func update(from point: CGPoint) {
        let center = CGPoint(x: dialSize / 2, y: dialSize / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        // Angle measured clockwise from the bottom of the dial.
        var angle = atan2(dx, -dy) * 180 / .pi  // -180...180, 0 == top
        angle += 180                            // 0...360, 0 == bottom
        let gapDegrees = gap * 360
        let usable = 360 - gapDegrees
        let adjusted = angle - gapDegrees / 2
        guard adjusted >= -12, adjusted <= usable + 12 else { return }
        let t = min(1, max(0, adjusted / usable))
        let raw = range.lowerBound + t * (range.upperBound - range.lowerBound)
        let snapped = (raw / step).rounded() * step
        let clamped = min(range.upperBound, max(range.lowerBound, snapped))
        if clamped != value {
            value = clamped
            onChanged?(clamped)
        }
    }
}

/// Compact read-only crown used in lists and summaries.
struct CrownBadge: View {
    let progress: Double
    var tint: Color = SkyPalette.gold
    var size: CGFloat = 44
    var label: String?

    var body: some View {
        ZStack {
            Circle()
                .stroke(SkyPalette.surfaceSunken, lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let label = label {
                Text(label)
                    .font(SkyFont.micro(size > 40 ? 13 : 10).weight(.bold))
                    .foregroundColor(SkyPalette.textPrimary)
            }
        }
        .frame(width: size, height: size)
    }
}
