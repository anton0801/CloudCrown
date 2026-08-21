//
//  SkyStates.swift
//  CloudCrown
//
//  The mandatory screen states: honest empty, loading, offline/cached,
//  error with retry, and success confirmation.
//

import SwiftUI

// MARK: - Honest empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    /// Explains what the very first action should be.
    var firstStepHint: String?

    var body: some View {
        VStack(spacing: SkySpacing.l) {
            ZStack {
                Circle()
                    .fill(SkyPalette.glow(SkyPalette.lightBlue, opacity: 0.45))
                    .frame(width: 140, height: 140)
                Circle()
                    .fill(SkyPalette.surface)
                    .frame(width: 84, height: 84)
                    .shadow(color: SkyPalette.azure.opacity(0.18), radius: 16, y: 6)
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(SkyPalette.azureGradient)
            }

            VStack(spacing: SkySpacing.s) {
                Text(title)
                    .font(SkyFont.title(19))
                    .foregroundColor(SkyPalette.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(SkyFont.body(14))
                    .foregroundColor(SkyPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SkySpacing.l)

            if let hint = firstStepHint {
                HStack(spacing: 6) {
                    Image(systemName: "1.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SkyPalette.gold)
                    Text(hint)
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, SkySpacing.m)
                .padding(.vertical, SkySpacing.s)
                .background(
                    RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                        .fill(SkyPalette.gold.opacity(0.10))
                )
                .padding(.horizontal, SkySpacing.l)
            }

            VStack(spacing: SkySpacing.s) {
                if let t = primaryTitle, let a = primaryAction {
                    SkyButton(title: t, icon: "plus", kind: .primary, action: a)
                }
                if let t = secondaryTitle, let a = secondaryAction {
                    SkyButton(title: t, kind: .ghost, action: a)
                }
            }
            .padding(.horizontal, SkySpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SkySpacing.xxl)
    }
}

// MARK: - Loading (skeleton, never duplicates real rows)

struct SkeletonBlock: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(SkyPalette.surfaceSunken)
            .frame(width: width, height: height)
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.65), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .rotationEffect(.degrees(12))
                .offset(x: shimmer ? 220 : -220)
                .mask(RoundedRectangle(cornerRadius: 6, style: .continuous))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
    }
}

struct LoadingCardsView: View {
    var count: Int = 3
    var body: some View {
        VStack(spacing: SkySpacing.m) {
            ForEach(0..<count, id: \.self) { _ in
                CloudCard {
                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        SkeletonBlock(height: 14, width: 130)
                        SkeletonBlock(height: 26)
                        SkeletonBlock(height: 12, width: 190)
                    }
                }
            }
        }
        .accessibilityLabel("Loading")
    }
}

// MARK: - Offline / cached

struct CachedBanner: View {
    let updatedAt: Date?
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: SkySpacing.s) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SkyPalette.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline — showing local snapshot")
                    .font(SkyFont.caption(12).weight(.semibold))
                    .foregroundColor(SkyPalette.textPrimary)
                Text(updatedAt.map { "May be outdated · captured \(RelativeTime.string(for: $0))" } ?? "No local snapshot stored yet")
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textSecondary)
            }
            Spacer(minLength: 0)
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Text("Retry").font(SkyFont.micro(12).weight(.semibold))
                        .foregroundColor(SkyPalette.azure)
                }
            }
        }
        .padding(.horizontal, SkySpacing.m)
        .padding(.vertical, SkySpacing.s)
        .background(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(SkyPalette.warning.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .strokeBorder(SkyPalette.warning.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Error with retry

struct ErrorStateView: View {
    let message: String
    var detail: String?
    var retryTitle: String = "Retry"
    let onRetry: () -> Void
    var onDismiss: (() -> Void)?

    var body: some View {
        CloudCard(tint: SkyPalette.danger) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: SkySpacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(SkyPalette.danger)
                    Text(message)
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = detail {
                    Text(detail)
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Your entered values were kept.")
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textTertiary)
                HStack(spacing: SkySpacing.s) {
                    SkyButton(title: retryTitle, icon: "arrow.clockwise", kind: .primary, action: onRetry)
                    if let onDismiss = onDismiss {
                        SkyButton(title: "Dismiss", kind: .ghost, fullWidth: false, action: onDismiss)
                    }
                }
            }
        }
    }
}

// MARK: - Success confirmation toast

struct SuccessToast: View {
    let title: String
    let changes: [String]

    var body: some View {
        HStack(alignment: .top, spacing: SkySpacing.s) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(SkyPalette.success)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SkyFont.headline(14))
                    .foregroundColor(SkyPalette.textPrimary)
                ForEach(changes, id: \.self) { change in
                    HStack(spacing: 4) {
                        Circle().fill(SkyPalette.textTertiary).frame(width: 3, height: 3)
                        Text(change)
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SkySpacing.m)
        .background(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(SkyPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .strokeBorder(SkyPalette.success.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: SkyPalette.deepBlue.opacity(0.14), radius: 18, y: 8)
        .padding(.horizontal, SkySpacing.l)
    }
}

/// Attaches a transient success toast to any screen.
struct ToastModifier: ViewModifier {
    @Binding var toast: ToastPayload?

    func body(content: Content) -> some View {
        content.overlay(
            VStack {
                Spacer()
                if let toast = toast {
                    SuccessToast(title: toast.title, changes: toast.changes)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, SkySpacing.l)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: toast?.id)
            , alignment: .bottom
        )
        .onChange(of: toast?.id) { newValue in
            guard newValue != nil else { return }
            let captured = newValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                if toast?.id == captured { toast = nil }
            }
        }
    }
}

struct ToastPayload: Equatable {
    let id = UUID()
    let title: String
    let changes: [String]
    init(title: String, changes: [String] = []) {
        self.title = title
        self.changes = changes
    }
}

extension View {
    func skyToast(_ toast: Binding<ToastPayload?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

// MARK: - Blocking reason (missing prerequisite)

/// Shown instead of an inaccurate result when a required prerequisite is absent.
struct MissingPrerequisiteView: View {
    let title: String
    let reason: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        CloudCard(tint: SkyPalette.violet) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: SkySpacing.s) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(SkyPalette.violet)
                    Text(title)
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                }
                Text(reason)
                    .font(SkyFont.caption(13))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SkyButton(title: actionTitle, icon: "arrow.right", kind: .secondary, action: action)
            }
        }
    }
}

// MARK: - Save failure

/// Shown when a write did not reach disk. The screen keeps the entered values
/// and stays in edit mode, because nothing was saved.
struct SaveErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            HStack(alignment: .top, spacing: SkySpacing.s) {
                Image(systemName: "externaldrive.badge.xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SkyPalette.danger)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Not saved")
                        .font(SkyFont.headline(14))
                        .foregroundColor(SkyPalette.textPrimary)
                    Text(message)
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Nothing was written and your entries were kept, so you can try again.")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            LightningLine()
                .stroke(SkyPalette.danger.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(height: 8)

            HStack(spacing: SkySpacing.l) {
                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(SkyFont.caption(13).weight(.semibold))
                            .foregroundColor(SkyPalette.danger)
                    }
                }
                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .font(SkyFont.caption(13).weight(.semibold))
                            .foregroundColor(SkyPalette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(SkySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(SkyPalette.danger.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .strokeBorder(SkyPalette.danger.opacity(0.30), lineWidth: 1)
        )
    }
}
