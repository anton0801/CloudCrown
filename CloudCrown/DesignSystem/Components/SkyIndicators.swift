//
//  SkyIndicators.swift
//  CloudCrown
//
//  Score rings, lightning warnings, source stamps and verdict pills.
//

import SwiftUI

// MARK: - Score ring

struct GlowRing: View {
    let score: Double?          // 0...100, nil = Unknown
    var verdictColor: Color = SkyPalette.azure
    var size: CGFloat = 92
    var caption: String?

    var body: some View {
        ZStack {
            Circle()
                .stroke(SkyPalette.surfaceSunken, lineWidth: 9)
            if let score = score {
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, score / 100))))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [verdictColor.opacity(0.65), verdictColor]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: verdictColor.opacity(0.4), radius: 8)
            } else {
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(
                        SkyPalette.unknown.opacity(0.4),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round, dash: [3, 6])
                    )
            }
            VStack(spacing: 0) {
                if let score = score {
                    Text("\(Int(score.rounded()))")
                        .font(SkyFont.metric(size > 80 ? 28 : 20))
                        .foregroundColor(SkyPalette.textPrimary)
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: size > 80 ? 22 : 16, weight: .bold))
                        .foregroundColor(SkyPalette.unknown)
                }
                if let caption = caption {
                    Text(caption)
                        .font(SkyFont.micro(9))
                        .foregroundColor(SkyPalette.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Lightning warning

/// Thin zig-zag line used to mark warnings, per the visual direction.
struct LightningLine: Shape {
    var segments: Int = 14
    var amplitude: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / CGFloat(max(1, segments))
        path.move(to: CGPoint(x: 0, y: rect.midY))
        for i in 1...max(1, segments) {
            let x = step * CGFloat(i)
            let y = rect.midY + (i % 2 == 0 ? amplitude : -amplitude)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

struct WarningBanner: View {
    enum Level { case warning, danger, info, unknown }

    let level: Level
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            HStack(alignment: .top, spacing: SkySpacing.s) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SkyFont.headline(14))
                        .foregroundColor(SkyPalette.textPrimary)
                    if let message = message {
                        Text(message)
                            .font(SkyFont.caption(12))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            LightningLine()
                .stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(height: 8)

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle).font(SkyFont.caption(13).weight(.semibold))
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(color)
                }
            }
        }
        .padding(SkySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(color.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .strokeBorder(color.opacity(0.28), lineWidth: 1)
        )
    }

    private var color: Color {
        switch level {
        case .warning: return SkyPalette.warning
        case .danger: return SkyPalette.danger
        case .info: return SkyPalette.azure
        case .unknown: return SkyPalette.unknown
        }
    }

    private var icon: String {
        switch level {
        case .warning: return "bolt.fill"
        case .danger: return "bolt.trianglebadge.exclamationmark.fill"
        case .info: return "info.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Source stamp

/// Shows Source + Last Updated + confidence for any externally sourced value.
/// This is mandatory next to every external data point in the app.
struct SourceStamp: View {
    let source: String
    let updatedAt: Date?
    var confidence: Confidence = .unknown
    var isStale: Bool = false
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isStale ? "clock.badge.exclamationmark" : "antenna.radiowaves.left.and.right")
                .font(.system(size: compact ? 8 : 9, weight: .semibold))
            Text(source)
                .font(SkyFont.micro(compact ? 9 : 10))
            Text("·").font(SkyFont.micro(compact ? 9 : 10))
            Text(updatedAt.map { RelativeTime.string(for: $0) } ?? "Never updated")
                .font(SkyFont.micro(compact ? 9 : 10))
            if !compact {
                Text("·").font(SkyFont.micro(10))
                HStack(spacing: 2) {
                    Circle().fill(confidence.color).frame(width: 5, height: 5)
                    Text(confidence.label).font(SkyFont.micro(10))
                }
            }
        }
        .foregroundColor(isStale ? SkyPalette.warning : SkyPalette.textTertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Verdict pill

struct VerdictPill: View {
    let verdict: WindowVerdict
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: verdict.icon).font(.system(size: compact ? 9 : 10, weight: .bold))
            Text(verdict.title).font(SkyFont.micro(compact ? 10 : 11).weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(Capsule().fill(verdict.color))
    }
}

// MARK: - Unknown value marker

struct UnknownTag: View {
    var text: String = "Unknown"
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "questionmark.circle").font(.system(size: 9, weight: .semibold))
            Text(text).font(SkyFont.micro(10).weight(.semibold))
        }
        .foregroundColor(SkyPalette.unknown)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(SkyPalette.unknown.opacity(0.14)))
    }
}
