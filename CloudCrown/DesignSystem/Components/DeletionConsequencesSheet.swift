//
//  DeletionConsequencesSheet.swift
//  CloudCrown
//
//  Related records are never removed invisibly: the consequences are listed and
//  the user chooses cancel, archive, or delete with safe detaching.
//

import SwiftUI

struct DeletionConsequencesSheet: View {

    let impact: DeletionImpact
    let onChoose: (DeletionStrategy) -> Void

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {

                        CloudCard(tint: SkyPalette.danger) {
                            VStack(alignment: .leading, spacing: SkySpacing.s) {
                                HStack(spacing: SkySpacing.s) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(SkyPalette.danger)
                                    Text("Delete “\(impact.entityTitle)”?")
                                        .font(SkyFont.headline(16))
                                        .foregroundColor(SkyPalette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text(impact.summary)
                                    .font(SkyFont.caption(13))
                                    .foregroundColor(SkyPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                LightningLine()
                                    .stroke(SkyPalette.danger.opacity(0.6),
                                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                    .frame(height: 8)
                            }
                        }

                        if !impact.dependents.isEmpty {
                            VStack(alignment: .leading, spacing: SkySpacing.m) {
                                SectionHeader(title: "What this affects",
                                              subtitle: "\(impact.dependents.count) linked record\(impact.dependents.count == 1 ? "" : "s")")
                                ForEach(impact.dependents) { dependent in
                                    HStack(spacing: SkySpacing.s) {
                                        Image(systemName: icon(for: dependent.type))
                                            .font(.system(size: 12))
                                            .foregroundColor(SkyPalette.warning)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(dependent.title)
                                                .font(SkyFont.caption(13).weight(.medium))
                                                .foregroundColor(SkyPalette.textPrimary)
                                            if !dependent.detail.isEmpty {
                                                Text(dependent.detail)
                                                    .font(SkyFont.micro(11))
                                                    .foregroundColor(SkyPalette.textSecondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Text(dependent.type.title)
                                            .font(SkyFont.micro(9).weight(.semibold))
                                            .foregroundColor(SkyPalette.textTertiary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(SkyPalette.surfaceSunken))
                                    }
                                    .padding(SkySpacing.m)
                                    .background(
                                        RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                                            .fill(SkyPalette.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                                            .strokeBorder(SkyPalette.hairline, lineWidth: 1)
                                    )
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: SkySpacing.m) {
                            SectionHeader(title: "Choose what happens")

                            optionCard(
                                title: "Archive instead",
                                message: "Keeps everything intact and hides it from active lists. Existing plans and history keep working. This is reversible.",
                                icon: "archivebox.fill",
                                accent: SkyPalette.azure
                            ) { choose(.archive) }

                            optionCard(
                                title: "Delete and detach safely",
                                message: impact.dependents.isEmpty
                                    ? "Removes this record. Nothing else references it."
                                    : "Removes this record, archives dependent plans and removes alert rules that can no longer match. Feedback history is kept so past results stay verifiable.",
                                icon: "trash.fill",
                                accent: SkyPalette.danger
                            ) { choose(.deleteAndDetach) }
                        }

                        Spacer(minLength: SkySpacing.xl)
                    }
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle("Consequences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { choose(.cancel) }
                        .foregroundColor(SkyPalette.textSecondary)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func choose(_ strategy: DeletionStrategy) {
        presentationMode.wrappedValue.dismiss()
        // Let the sheet finish dismissing before mutating the underlying list.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onChoose(strategy)
        }
    }

    private func optionCard(title: String, message: String, icon: String, accent: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CloudCard(tint: accent) {
                HStack(alignment: .top, spacing: SkySpacing.m) {
                    ZStack {
                        Circle().fill(accent.opacity(0.13)).frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text(message)
                            .font(SkyFont.caption(12))
                            .foregroundColor(SkyPalette.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(SkyPalette.hairline)
                }
            }
        }
        .buttonStyle(SkyPressStyle())
    }

    private func icon(for type: EntityType) -> String {
        switch type {
        case .plan: return "calendar"
        case .alert: return "bell.fill"
        case .feedback: return "star.bubble.fill"
        case .place: return "mappin"
        case .activity: return "figure.walk"
        case .profile: return "slider.horizontal.3"
        case .snapshot: return "cloud.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
