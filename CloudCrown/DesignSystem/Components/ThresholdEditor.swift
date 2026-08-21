//
//  ThresholdEditor.swift
//  CloudCrown
//
//  Shared editor for one comfort threshold. Undefined stays undefined —
//  turning a bound off restores Unknown rather than writing zero.
//

import SwiftUI

struct ThresholdEditor: View {

    let metric: MetricKind
    @Binding var threshold: ComfortThreshold
    var settings: AppSettings
    var showsMinimum: Bool = true
    var showsMaximum: Bool = true

    @State private var editingBound: Bound = .maximum

    enum Bound { case minimum, maximum }

    private var activeValue: Binding<Double> {
        Binding(
            get: {
                switch editingBound {
                case .minimum: return threshold.minValue ?? defaultFor(.minimum)
                case .maximum: return threshold.maxValue ?? defaultFor(.maximum)
                }
            },
            set: { newValue in
                switch editingBound {
                case .minimum: threshold.minValue = newValue
                case .maximum: threshold.maxValue = newValue
                }
                normalize()
            }
        )
    }

    private func defaultFor(_ bound: Bound) -> Double {
        let range = metric.uiRange
        return bound == .minimum
            ? range.lowerBound + (range.upperBound - range.lowerBound) * 0.25
            : range.lowerBound + (range.upperBound - range.lowerBound) * 0.6
    }

    /// Keeps min ≤ max so an impossible range can never be saved.
    private func normalize() {
        if let min = threshold.minValue, let max = threshold.maxValue, min > max {
            if editingBound == .minimum { threshold.maxValue = min } else { threshold.minValue = max }
        }
    }

    private var isActiveBoundSet: Bool {
        editingBound == .minimum ? threshold.minValue != nil : threshold.maxValue != nil
    }

    var body: some View {
        VStack(spacing: SkySpacing.m) {
            HStack(spacing: SkySpacing.s) {
                Image(systemName: metric.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(metric.accentColor)
                Text(metric.title)
                    .font(SkyFont.headline(15))
                    .foregroundColor(SkyPalette.textPrimary)
                Spacer()
                Text(settings.unitSymbol(for: metric))
                    .font(SkyFont.micro(11).weight(.semibold))
                    .foregroundColor(SkyPalette.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(SkyPalette.surfaceSunken))
            }

            if showsMinimum && showsMaximum {
                SkySegmented(
                    options: [Bound.minimum, Bound.maximum],
                    titleFor: { $0 == .minimum ? "Minimum" : "Maximum" },
                    selection: $editingBound
                )
            }

            CrownDial(
                title: editingBound == .minimum ? "Lowest acceptable" : "Highest acceptable",
                unit: settings.unitSymbol(for: metric),
                value: activeValue,
                range: displayRange,
                step: metric.decimals > 0 ? 0.5 : 1,
                tint: metric.accentColor,
                isSet: isActiveBoundSet
            )

            HStack(spacing: SkySpacing.s) {
                if showsMinimum {
                    boundToggle(.minimum, label: "Min", value: threshold.minValue)
                }
                if showsMaximum {
                    boundToggle(.maximum, label: "Max", value: threshold.maxValue)
                }
            }

            if !threshold.isDefined {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle").font(.system(size: 11))
                    Text("Undefined — this metric will not block or score a window.")
                        .font(SkyFont.micro(11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(SkyPalette.unknown)
            }
        }
    }

    /// The dial works in the user's display unit, then converts back to canonical.
    private var displayRange: ClosedRange<Double> {
        let range = metric.uiRange
        let lower = settings.display(range.lowerBound, for: metric)
        let upper = settings.display(range.upperBound, for: metric)
        return min(lower, upper)...max(lower, upper)
    }

    private func boundToggle(_ bound: Bound, label: String, value: Double?) -> some View {
        Button {
            editingBound = bound
            switch bound {
            case .minimum:
                threshold.minValue = threshold.minValue == nil ? defaultFor(.minimum) : nil
            case .maximum:
                threshold.maxValue = threshold.maxValue == nil ? defaultFor(.maximum) : nil
            }
            normalize()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: value != nil ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(SkyFont.micro(10).weight(.semibold))
                    Text(value.map { SkyFormat.number($0, decimals: metric.decimals) } ?? "off")
                        .font(SkyFont.micro(12).weight(.bold))
                }
            }
            .foregroundColor(value != nil ? metric.accentColor : SkyPalette.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SkySpacing.s)
            .background(
                RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                    .fill(value != nil ? metric.accentColor.opacity(0.10) : SkyPalette.surfaceSunken)
            )
        }
        .buttonStyle(SkyPressStyle())
    }
}
