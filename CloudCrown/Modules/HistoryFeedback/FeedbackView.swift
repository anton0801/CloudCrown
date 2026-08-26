//
//  FeedbackView.swift
//  CloudCrown
//

import SwiftUI

struct FeedbackView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: FeedbackPresenter
    @StateObject private var router: FeedbackRouter

    init(presenter: @autoclosure @escaping () -> FeedbackPresenter,
         router: @autoclosure @escaping () -> FeedbackRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            SkyBackground()
            if presenter.plan != nil {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        headerCard
                        if let message = presenter.saveError {
                            SaveErrorBanner(message: message,
                                            onRetry: presenter.save,
                                            onDismiss: presenter.dismissSaveError)
                        }
                        ratingCard
                        tagsCard
                        actualConditionsCard
                        noteCard
                        preservationCard
                        Spacer(minLength: 110)
                    }
                    .padding(SkySpacing.l)
                }

                VStack {
                    Spacer()
                    saveBar
                }
            } else {
                EmptyStateView(icon: "calendar.badge.exclamationmark",
                               title: "Plan unavailable",
                               message: "This plan no longer exists, so there is nothing to review.")
            }
        }
        .navigationTitle("How Did It Go?")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presenter.onAppear() }
        .skyToast($presenter.toast)
        .onChange(of: router.didFinish) { finished in
            if finished { presentationMode.wrappedValue.dismiss() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerCard: some View {
        if let plan = presenter.plan {
            CloudCard(tint: SkyPalette.violet) {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text(plan.title)
                        .font(SkyFont.headline(16))
                        .foregroundColor(SkyPalette.textPrimary)
                    Text("\(plan.window.dayText()) · \(plan.window.timeRangeText())")
                        .font(SkyFont.caption(13))
                        .foregroundColor(SkyPalette.textSecondary)
                    HStack(spacing: SkySpacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Forecast score").font(SkyFont.micro(10)).foregroundColor(SkyPalette.textTertiary)
                            if let score = plan.window.score {
                                Text("\(Int(score.rounded()))")
                                    .font(SkyFont.metric(20))
                                    .foregroundColor(SkyPalette.azure)
                            } else {
                                UnknownTag()
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Predicted").font(SkyFont.micro(10)).foregroundColor(SkyPalette.textTertiary)
                            Text(plan.window.verdict.title)
                                .font(SkyFont.caption(13).weight(.semibold))
                                .foregroundColor(plan.window.verdict.color)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Rating

    private var ratingCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Comfort Rating", subtitle: "Optional — but Insights needs it")

                HStack(spacing: SkySpacing.s) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            presenter.comfortRating = presenter.comfortRating == value ? nil : value
                        } label: {
                            Image(systemName: (presenter.comfortRating ?? 0) >= value ? "star.fill" : "star")
                                .font(.system(size: 27))
                                .foregroundColor((presenter.comfortRating ?? 0) >= value
                                                 ? SkyPalette.gold : SkyPalette.hairline)
                        }
                        .buttonStyle(SkyPressStyle())
                    }
                    Spacer()
                    if presenter.comfortRating == nil {
                        UnknownTag(text: "Not rated")
                    }
                }

                Text(presenter.insightsNote)
                    .font(SkyFont.micro(11))
                    .foregroundColor(presenter.comfortRating == nil ? SkyPalette.warning : SkyPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().background(SkyPalette.divider)

                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text("Would Repeat")
                        .font(SkyFont.micro(11).weight(.semibold))
                        .foregroundColor(SkyPalette.textTertiary)
                    HStack(spacing: SkySpacing.s) {
                        repeatButton(true, "Yes", "hand.thumbsup.fill", SkyPalette.success)
                        repeatButton(false, "No", "hand.thumbsdown.fill", SkyPalette.danger)
                        if presenter.wouldRepeat != nil {
                            Button { presenter.wouldRepeat = nil } label: {
                                Text("Clear")
                                    .font(SkyFont.micro(11).weight(.semibold))
                                    .foregroundColor(SkyPalette.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func repeatButton(_ value: Bool, _ title: String, _ icon: String, _ color: Color) -> some View {
        Button { presenter.wouldRepeat = value } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(SkyFont.caption(13).weight(.semibold))
            }
            .foregroundColor(presenter.wouldRepeat == value ? .white : color)
            .padding(.horizontal, SkySpacing.l)
            .padding(.vertical, SkySpacing.s)
            .background(
                Capsule().fill(presenter.wouldRepeat == value
                               ? AnyShapeStyle(color)
                               : AnyShapeStyle(color.opacity(0.12)))
            )
        }
        .buttonStyle(SkyPressStyle())
    }

    // MARK: - Tags

    private var tagsCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "What stood out", subtitle: "Used to find repeated mismatches")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: SkySpacing.s)],
                          spacing: SkySpacing.s) {
                    ForEach(FeedbackTag.allCases) { tag in
                        Button { presenter.toggleTag(tag) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tag.icon).font(.system(size: 11, weight: .semibold))
                                Text(tag.title)
                                    .font(SkyFont.micro(11).weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                            }
                            .foregroundColor(presenter.selectedTags.contains(tag) ? .white : tag.color)
                            .padding(.horizontal, SkySpacing.m)
                            .padding(.vertical, SkySpacing.s)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                    .fill(presenter.selectedTags.contains(tag)
                                          ? AnyShapeStyle(tag.color)
                                          : AnyShapeStyle(tag.color.opacity(0.10)))
                            )
                        }
                        .buttonStyle(SkyPressStyle())
                    }
                }
            }
        }
    }

    // MARK: - Actual conditions

    private var actualConditionsCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Actual Conditions",
                              subtitle: "Optional — only what you actually observed")

                if presenter.editableMetrics.isEmpty {
                    Text("This plan's window carried no measurable values, so there is nothing to compare against.")
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(presenter.editableMetrics, id: \.self) { metric in
                        actualRow(metric)
                        if metric != presenter.editableMetrics.last {
                            Divider().background(SkyPalette.divider)
                        }
                    }
                    Text("Leaving a field empty keeps it Unknown. Nothing is assumed to have matched.")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func actualRow(_ metric: MetricKind) -> some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            HStack(spacing: SkySpacing.s) {
                Image(systemName: metric.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(metric.accentColor)
                    .frame(width: 18)
                Text(metric.title)
                    .font(SkyFont.caption(13).weight(.medium))
                    .foregroundColor(SkyPalette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Forecast").font(SkyFont.micro(9)).foregroundColor(SkyPalette.textTertiary)
                    Text(presenter.settings.format(presenter.forecastValue(metric), for: metric))
                        .font(SkyFont.micro(12).weight(.semibold))
                        .foregroundColor(SkyPalette.azure)
                }
            }

            HStack(spacing: SkySpacing.s) {
                TextField("Actual", text: Binding(
                    get: {
                        guard let value = presenter.actualValues[metric] else { return "" }
                        return SkyFormat.number(presenter.settings.display(value, for: metric),
                                                decimals: metric.decimals)
                    },
                    set: { text in
                        let cleaned = text.replacingOccurrences(of: ",", with: ".")
                        if cleaned.isEmpty {
                            presenter.setActual(metric, nil)
                        } else if let displayed = Double(cleaned) {
                            // Convert the displayed unit back to canonical storage.
                            let canonical = presenter.settings.temperatureUnit == .fahrenheit
                                && (metric == .temperature || metric == .apparentTemperature)
                                ? presenter.settings.temperatureUnit.toCanonical(displayed)
                                : (metric == .windSpeed || metric == .windGust)
                                    ? presenter.settings.speedUnit.toCanonical(displayed)
                                    : displayed
                            presenter.setActual(metric, canonical)
                        }
                    }
                ))
                .font(SkyFont.metric(15))
                .keyboardType(.numbersAndPunctuation)
                .padding(SkySpacing.s)
                .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                    .fill(SkyPalette.surfaceSunken))

                Text(presenter.settings.unitSymbol(for: metric))
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textTertiary)
                    .frame(width: 38, alignment: .leading)

                if let difference = presenter.difference(metric) {
                    Text(SkyFormat.signed(presenter.settings.display(difference, for: metric) -
                                          (metric == .temperature || metric == .apparentTemperature
                                           ? presenter.settings.display(0, for: metric) : 0),
                                          decimals: metric.decimals))
                        .font(SkyFont.micro(12).weight(.bold))
                        .foregroundColor(abs(difference) > 0.001 ? SkyPalette.warning : SkyPalette.success)
                        .frame(width: 52, alignment: .trailing)
                } else {
                    UnknownTag(text: "—").frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Note

    private var noteCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                SectionHeader(title: "Note", subtitle: "Optional")
                TextEditor(text: $presenter.note)
                    .foregroundColor(SkyPalette.textPrimary)
                    .font(SkyFont.body(14))
                    .frame(height: 88)
                    .padding(SkySpacing.s)
                    .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                        .fill(SkyPalette.surfaceSunken))
            }
        }
    }

    // MARK: - Preservation

    @ViewBuilder
    private var preservationCard: some View {
        if let plan = presenter.plan {
            CloudCard(tint: SkyPalette.violet) {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    HStack(spacing: SkySpacing.s) {
                        Image(systemName: "lock.doc.fill").foregroundColor(SkyPalette.violet)
                        Text("The forecast is not rewritten")
                            .font(SkyFont.headline(14))
                            .foregroundColor(SkyPalette.textPrimary)
                    }
                    Text("Your review is stored beside the original snapshot, not on top of it. Both remain readable, which is what lets Insights compare what was predicted with what you experienced.")
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SourceStamp(source: "Snapshot \(String(plan.window.snapshotID.uuidString.prefix(6)))",
                                updatedAt: plan.window.snapshotCapturedAt,
                                confidence: .high, compact: true)
                }
            }
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        HStack(spacing: SkySpacing.s) {
            SkyButton(title: "Cancel", kind: .ghost, fullWidth: false, action: presenter.cancel)
            SkyButton(title: "Save Feedback", icon: "checkmark", kind: .primary,
                      isLoading: presenter.isSaving,
                      isEnabled: presenter.canSave,
                      action: presenter.save)
        }
        .padding(.horizontal, SkySpacing.l)
        .padding(.top, SkySpacing.m)
        .padding(.bottom, SkySpacing.l)
        .background(
            LinearGradient(colors: [SkyPalette.cloudWhite.opacity(0), SkyPalette.cloudWhite],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}
