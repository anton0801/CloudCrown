//
//  OnboardingLimitsEditor.swift
//  CloudCrown
//

import SwiftUI

struct OnboardingLimitsEditor: View {

    @ObservedObject var presenter: OnboardingPresenter
    @Environment(\.presentationMode) private var presentationMode
    @State private var selectedMetric: MetricKind = .temperature

    private var thresholdBinding: Binding<ComfortThreshold> {
        Binding(
            get: {
                presenter.profileDraft.threshold(for: selectedMetric)
                    ?? ComfortThreshold(metric: selectedMetric, minValue: nil, maxValue: nil)
            },
            set: { updated in
                if let index = presenter.profileDraft.thresholds.firstIndex(where: { $0.metric == selectedMetric }) {
                    presenter.profileDraft.thresholds[index] = updated
                } else {
                    presenter.profileDraft.thresholds.append(updated)
                }
            }
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SkySpacing.l) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SkySpacing.s) {
                                ForEach(ComfortProfile.coreMetrics, id: \.self) { metric in
                                    let isDefined = presenter.profileDraft.threshold(for: metric)?.isDefined == true
                                    SkyChip(
                                        title: metric.shortTitle,
                                        icon: isDefined ? "checkmark" : metric.icon,
                                        color: metric.accentColor,
                                        isSelected: selectedMetric == metric
                                    ) {
                                        withAnimation(.easeOut(duration: 0.2)) { selectedMetric = metric }
                                    }
                                }
                            }
                            .padding(.horizontal, SkySpacing.l)
                        }

                        CloudCard {
                            ThresholdEditor(
                                metric: selectedMetric,
                                threshold: thresholdBinding,
                                settings: .default,
                                showsMinimum: selectedMetric == .temperature,
                                showsMaximum: true
                            )
                        }
                        .padding(.horizontal, SkySpacing.l)

                        CloudCard(tint: SkyPalette.violet) {
                            VStack(alignment: .leading, spacing: SkySpacing.s) {
                                Text("Defined so far")
                                    .font(SkyFont.headline(14))
                                    .foregroundColor(SkyPalette.textPrimary)
                                ForEach(ComfortProfile.coreMetrics, id: \.self) { metric in
                                    HStack {
                                        Text(metric.title)
                                            .font(SkyFont.caption(13))
                                            .foregroundColor(SkyPalette.textSecondary)
                                        Spacer()
                                        if let t = presenter.profileDraft.threshold(for: metric), t.isDefined {
                                            Text(t.summary)
                                                .font(SkyFont.micro(12).weight(.semibold))
                                                .foregroundColor(SkyPalette.textPrimary)
                                        } else {
                                            UnknownTag(text: "Not set")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, SkySpacing.l)

                        Spacer(minLength: SkySpacing.xl)
                    }
                    .padding(.top, SkySpacing.m)
                }
            }
            .navigationTitle("Set My Limits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presenter.saveCustomLimits()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(SkyFont.headline(15))
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
