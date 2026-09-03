//
//  OnboardingView.swift
//  CloudCrown
//

import SwiftUI

struct OnboardingView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: OnboardingPresenter
    @StateObject private var router: OnboardingRouter

    init(presenter: @autoclosure @escaping () -> OnboardingPresenter,
         router: @autoclosure @escaping () -> OnboardingRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            OlympusOnboardingBackground(step: presenter.step.rawValue)

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        titleBlock
                        stepContent
                    }
                    .padding(.horizontal, SkySpacing.l)
                    .padding(.bottom, SkySpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .onAppear { presenter.onAppear() }
        .sheet(isPresented: $router.showsLimitsEditor) {
            OnboardingLimitsEditor(presenter: presenter)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: SkySpacing.m) {
            HStack {
                if presenter.step.rawValue > 0 {
                    Button(action: presenter.goBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                            Text("Back").font(SkyFont.caption(13))
                        }
                        .foregroundColor(SkyPalette.textSecondary)
                    }
                }
                Spacer()
                Text("Step \(presenter.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SkyPalette.surfaceSunken)
                    Capsule()
                        .fill(SkyPalette.azureGradient)
                        .frame(width: geo.size.width * presenter.progress)
                        .shadow(color: SkyPalette.azure.opacity(0.4), radius: 6, y: 2)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, SkySpacing.l)
        .padding(.top, SkySpacing.m)
        .padding(.bottom, SkySpacing.l)
    }

    private var titleBlock: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                Text(presenter.step.title)
                    .font(SkyFont.display(30))
                    .foregroundColor(SkyPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(presenter.step.subtitle)
                    .font(SkyFont.body(15))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 76)

            OlympusAccent(kind: onboardingAccent, size: 60)
        }
    }

    private var onboardingAccent: OlympusAccent.Kind {
        switch presenter.step {
        case .problem: return .lightning
        case .limits: return .shield
        case .explanation: return .hourglass
        case .firstActivity: return .podium
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch presenter.step {
        case .problem: problemStep
        case .limits: limitsStep
        case .explanation: explanationStep
        case .firstActivity: activityStep
        }
    }

    // MARK: - Step 1

    private var problemStep: some View {
        VStack(spacing: SkySpacing.m) {
            CelestialCard {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    Image(systemName: "cloud.sun.bolt.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                    Text("“22° and partly cloudy” is not a decision.")
                        .font(SkyFont.title(19))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("It does not tell you whether the wind blocks your run, whether UV lands in the hour you are free, or whether the air is worse than you tolerate.")
                        .font(SkyFont.body(14))
                        .foregroundColor(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    Text("How the sections connect")
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                    ForEach(Array(chainItems.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: SkySpacing.m) {
                            VStack(spacing: 0) {
                                ZStack {
                                    Circle().fill(SkyPalette.azure.opacity(0.12)).frame(width: 26, height: 26)
                                    Text("\(index + 1)")
                                        .font(SkyFont.micro(12).weight(.bold))
                                        .foregroundColor(SkyPalette.azure)
                                }
                                if index < chainItems.count - 1 {
                                    Rectangle()
                                        .fill(SkyPalette.hairline)
                                        .frame(width: 1.5, height: 22)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.0)
                                    .font(SkyFont.caption(13).weight(.semibold))
                                    .foregroundColor(SkyPalette.textPrimary)
                                Text(item.1)
                                    .font(SkyFont.micro(11))
                                    .foregroundColor(SkyPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.bottom, index < chainItems.count - 1 ? SkySpacing.s : 0)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            CloudCard(tint: SkyPalette.violet) {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    HStack(spacing: SkySpacing.s) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(SkyPalette.violet)
                        Text("Where the numbers come from")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                    }
                    Text("Conditions are fetched from Open-Meteo — a public forecast and air-quality service. Every value shows its source, when it was updated and how confident it is. If a measurement is missing, CloudCrown says Unknown instead of showing zero.")
                        .font(SkyFont.caption(13))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SourceStamp(source: "Open-Meteo", updatedAt: nil, confidence: .unknown)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var chainItems: [(String, String)] {
        [
            ("Comfort Profile", "Your personal limits for temperature, rain, wind, UV, air and pollen."),
            ("Activity Template", "Which conditions block a window, and which only shape its score."),
            ("Place", "Coordinates and time zone that conditions are fetched for."),
            ("Window Finder", "Concrete intervals that satisfy your limits, each with an explanation."),
            ("Plan & History", "Save a window, get told when it changes, then record how it actually felt.")
        ]
    }

    // MARK: - Step 2

    private var limitsStep: some View {
        VStack(spacing: SkySpacing.m) {
            choiceCard(
                title: "Set My Limits",
                message: "Define each threshold yourself. Anything you leave undefined stays Unknown and will not be used to judge a window.",
                icon: "slider.horizontal.below.square.filled.and.square",
                accent: SkyPalette.azure,
                isSelected: presenter.limitsChoice == .custom,
                badge: presenter.limitsChoice == .custom ? "\(presenter.profileDraft.definedCount) defined" : nil,
                action: presenter.chooseCustomLimits
            )

            choiceCard(
                title: "Use General Defaults",
                message: ComfortProfile.generalDefaultsDisclaimer,
                icon: "wand.and.stars",
                accent: SkyPalette.gold,
                isSelected: presenter.limitsChoice == .generalDefaults,
                badge: presenter.limitsChoice == .generalDefaults ? "General, not medical" : nil,
                action: presenter.applyGeneralDefaults
            )

            if presenter.limitsChoice == .generalDefaults {
                WarningBanner(
                    level: .warning,
                    title: "These are general starting points",
                    message: "They are not medical guidance and not tuned to you. Change any limit later in Comfort Profile — every window is re-scored from the same record."
                )
            }

            if presenter.limitsChoice != nil {
                CloudCard {
                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        Text("Your limits so far")
                            .font(SkyFont.headline(14))
                            .foregroundColor(SkyPalette.textPrimary)
                        ForEach(ComfortProfile.coreMetrics, id: \.self) { metric in
                            HStack {
                                Image(systemName: metric.icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(metric.accentColor)
                                    .frame(width: 20)
                                Text(metric.title)
                                    .font(SkyFont.caption(13))
                                    .foregroundColor(SkyPalette.textSecondary)
                                Spacer()
                                if let threshold = presenter.profileDraft.threshold(for: metric), threshold.isDefined {
                                    Text(threshold.summary)
                                        .font(SkyFont.micro(12).weight(.semibold))
                                        .foregroundColor(SkyPalette.textPrimary)
                                } else {
                                    UnknownTag(text: "Not set")
                                }
                            }
                        }
                        if presenter.limitsChoice == .custom {
                            Button(action: presenter.chooseCustomLimits) {
                                Text("Edit limits")
                                    .font(SkyFont.caption(13).weight(.semibold))
                                    .foregroundColor(SkyPalette.azure)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }

    private func choiceCard(title: String, message: String, icon: String, accent: Color,
                            isSelected: Bool, badge: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CloudCard(tint: accent) {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    HStack(spacing: SkySpacing.s) {
                        ZStack {
                            Circle().fill(accent.opacity(0.14)).frame(width: 36, height: 36)
                            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundColor(accent)
                        }
                        Text(title)
                            .font(SkyFont.headline(16))
                            .foregroundColor(SkyPalette.textPrimary)
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundColor(isSelected ? accent : SkyPalette.hairline)
                    }
                    Text(message)
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge = badge {
                        SkyChip(title: badge, icon: "info.circle", color: accent)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: SkyRadius.large, style: .continuous)
                    .strokeBorder(isSelected ? accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(SkyPressStyle())
    }

    // MARK: - Step 3

    private var explanationStep: some View {
        VStack(spacing: SkySpacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.system(size: 11))
                Text("Illustration of the explanation format — not your data")
                    .font(SkyFont.micro(11).weight(.semibold))
            }
            .foregroundColor(SkyPalette.violet)
            .padding(.horizontal, SkySpacing.m)
            .padding(.vertical, SkySpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                    .fill(SkyPalette.violet.opacity(0.10))
            )

            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sat 12 Apr · 07:30 – 08:30")
                                .font(SkyFont.headline(15))
                                .foregroundColor(SkyPalette.textPrimary)
                            Text("Example window")
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.textTertiary)
                        }
                        Spacer()
                        GlowRing(score: 82, verdictColor: SkyPalette.verdictBest, size: 62, caption: "score")
                    }

                    Divider().background(SkyPalette.divider)

                    Text("Required conditions")
                        .font(SkyFont.micro(11).weight(.semibold))
                        .foregroundColor(SkyPalette.textTertiary)
                    exampleRow(.pass, "Rain chance ≤ 30%", "reaches 12% at 08:00")
                    exampleRow(.pass, "Wind ≤ 25 km/h", "peaks at 14 km/h at 07:30")
                    exampleRow(.unknown, "Pollen ≤ 50 grains/m³", "not available for this place")

                    Text("Preferred conditions")
                        .font(SkyFont.micro(11).weight(.semibold))
                        .foregroundColor(SkyPalette.textTertiary)
                        .padding(.top, 2)
                    examplePreferred("Temperature near 18 °C", 40, 34.8)
                    examplePreferred("Lower UV is better", 30, 27.0)
                    examplePreferred("Lower air quality index", 30, 20.4)
                }
            }

            CloudCard(tint: SkyPalette.violet) {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    HStack(spacing: SkySpacing.s) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(SkyPalette.violet)
                        Text("Nothing is hidden")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                    }
                    ForEach(guarantees, id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(SkyPalette.violet).frame(width: 4, height: 4).padding(.top, 6)
                            Text(line)
                                .font(SkyFont.caption(12))
                                .foregroundColor(SkyPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var guarantees: [String] {
        [
            "A required condition that fails blocks the window — it is never quietly downgraded to a lower score.",
            "A measurement that is missing shows as Unknown, and that window can never be called a Best Match.",
            "Every score records the rules version and the exact forecast snapshot it came from.",
            "When the forecast is updated, the old explanation is marked Superseded rather than silently rewritten."
        ]
    }

    private func exampleRow(_ outcome: RuleOutcome, _ rule: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: SkySpacing.s) {
            Image(systemName: outcome.icon)
                .font(.system(size: 13))
                .foregroundColor(outcome.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule)
                    .font(SkyFont.caption(13).weight(.medium))
                    .foregroundColor(SkyPalette.textPrimary)
                Text(detail)
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func examplePreferred(_ title: String, _ weight: Int, _ earned: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(SkyFont.caption(12))
                    .foregroundColor(SkyPalette.textPrimary)
                Spacer()
                Text("\(String(format: "%.1f", earned)) / \(weight)")
                    .font(SkyFont.micro(11).weight(.semibold))
                    .foregroundColor(SkyPalette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SkyPalette.surfaceSunken)
                    Capsule()
                        .fill(SkyPalette.azureGradient)
                        .frame(width: geo.size.width * (earned / Double(weight)))
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Step 4

    private var activityStep: some View {
        VStack(spacing: SkySpacing.m) {
            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    SectionHeader(title: "Activity", subtitle: "You can add required conditions later")

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: SkySpacing.s)], spacing: SkySpacing.s) {
                        ForEach(ActivityKind.allCases) { kind in
                            Button {
                                presenter.selectActivityKind(kind)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: kind.icon)
                                        .font(.system(size: 17, weight: .medium))
                                    Text(kind.title)
                                        .font(SkyFont.micro(11).weight(.medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .foregroundColor(presenter.activityKind == kind ? .white : kind.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SkySpacing.m)
                                .background(
                                    RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                                        .fill(presenter.activityKind == kind
                                              ? AnyShapeStyle(kind.accent)
                                              : AnyShapeStyle(kind.accent.opacity(0.10)))
                                )
                            }
                            .buttonStyle(SkyPressStyle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(SkyFont.micro(11).weight(.semibold))
                            .foregroundColor(SkyPalette.textTertiary)
                        TextField("Morning walk", text: $presenter.activityName)
                            .foregroundColor(SkyPalette.textPrimary)
                            .font(SkyFont.body(15))
                            .padding(SkySpacing.m)
                            .background(
                                RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                    .fill(SkyPalette.surfaceSunken)
                            )
                        if presenter.activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("A name is required so you can recognise this activity later.")
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.danger)
                        }
                    }

                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        HStack {
                            Text("Duration")
                                .font(SkyFont.micro(11).weight(.semibold))
                                .foregroundColor(SkyPalette.textTertiary)
                            Spacer()
                            Text(SkyFormat.duration(minutes: Int(presenter.durationMinutes)))
                                .font(SkyFont.caption(13).weight(.semibold))
                                .foregroundColor(SkyPalette.textPrimary)
                        }
                        Slider(value: $presenter.durationMinutes, in: 15...240, step: 15)
                            .tint(SkyPalette.azure)
                    }
                }
            }

            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    SectionHeader(title: "Place", subtitle: "Conditions are fetched per place")

                    if let place = presenter.chosenPlace {
                        HStack(spacing: SkySpacing.s) {
                            Image(systemName: place.source.icon)
                                .foregroundColor(SkyPalette.success)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name)
                                    .font(SkyFont.headline(15))
                                    .foregroundColor(SkyPalette.textPrimary)
                                Text("\(place.source.title) · \(place.timeZoneIdentifier)")
                                    .font(SkyFont.micro(11))
                                    .foregroundColor(SkyPalette.textSecondary)
                            }
                            Spacer()
                            Button(action: presenter.clearChosenPlace) {
                                Text("Change")
                                    .font(SkyFont.micro(12).weight(.semibold))
                                    .foregroundColor(SkyPalette.azure)
                            }
                        }
                        .padding(SkySpacing.m)
                        .background(
                            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                                .fill(SkyPalette.success.opacity(0.08))
                        )
                    } else {
                        SkyButton(
                            title: presenter.isResolvingLocation ? "Getting location…" : "Use Current Location",
                            icon: "location.fill",
                            kind: .secondary,
                            isLoading: presenter.isResolvingLocation,
                            action: presenter.useCurrentLocation
                        )

                        if let message = presenter.locationMessage {
                            WarningBanner(level: .warning, title: "Location unavailable", message: message + " Searching by name still works.")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Or search for a place")
                                .font(SkyFont.micro(11).weight(.semibold))
                                .foregroundColor(SkyPalette.textTertiary)
                            HStack(spacing: SkySpacing.s) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(SkyPalette.textTertiary)
                                TextField("City or district", text: $presenter.searchQuery)
                                    .foregroundColor(SkyPalette.textPrimary)
                                    .font(SkyFont.body(15))
                                    .autocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .onChange(of: presenter.searchQuery) { presenter.search($0) }
                                if presenter.isSearching {
                                    ProgressView().scaleEffect(0.7)
                                }
                            }
                            .padding(SkySpacing.m)
                            .background(
                                RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                    .fill(SkyPalette.surfaceSunken)
                            )
                        }

                        if let error = presenter.searchError {
                            Text(error)
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.warning)
                        }

                        ForEach(presenter.searchResults) { result in
                            Button {
                                presenter.selectSearchResult(result)
                            } label: {
                                HStack(spacing: SkySpacing.s) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(SkyPalette.azure)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.name)
                                            .font(SkyFont.caption(14).weight(.medium))
                                            .foregroundColor(SkyPalette.textPrimary)
                                        Text(result.subtitle)
                                            .font(SkyFont.micro(11))
                                            .foregroundColor(SkyPalette.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(SkyPalette.azure)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(SkyPressStyle())
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").font(.system(size: 11))
                Text("Precise location is only requested when you tap Use Current Location. Everything works without it.")
                    .font(SkyFont.micro(11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(SkyPalette.textTertiary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: SkySpacing.s) {
            if presenter.step == .firstActivity && !presenter.canAdvance {
                Text(presenter.chosenPlace == nil
                     ? "Choose a place to continue — CloudCrown will not invent one."
                     : "Give the activity a name to continue.")
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            SkyButton(
                title: presenter.advanceTitle,
                icon: presenter.step == .firstActivity ? "checkmark" : "arrow.right",
                kind: .primary,
                isLoading: presenter.isSaving,
                isEnabled: presenter.canAdvance,
                action: presenter.advance
            )
        }
        .padding(.horizontal, SkySpacing.l)
        .padding(.top, SkySpacing.m)
        .padding(.bottom, SkySpacing.l)
        .background(
            LinearGradient(colors: [SkyPalette.cloudWhite.opacity(0), SkyPalette.cloudWhite, SkyPalette.cloudWhite],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}
