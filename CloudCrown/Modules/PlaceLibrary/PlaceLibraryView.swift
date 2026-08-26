//
//  PlaceLibraryView.swift
//  CloudCrown
//

import SwiftUI

struct PlaceLibraryView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: PlaceLibraryPresenter
    @StateObject private var router: PlaceLibraryRouter

    init(presenter: @autoclosure @escaping () -> PlaceLibraryPresenter,
         router: @autoclosure @escaping () -> PlaceLibraryRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SkySpacing.l) {
                    if let message = presenter.saveError {
                        SaveErrorBanner(message: message, onDismiss: presenter.dismissSaveError)
                    }
                    addSection
                    if presenter.isEmpty && presenter.searchResults.isEmpty {
                        emptyState
                    } else {
                        activeSection
                        archivedSection
                    }
                    Spacer(minLength: SkySpacing.xxl)
                }
                .padding(SkySpacing.l)
            }
        }
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: presenter.startAdding) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(SkyPalette.azure)
            }
        }
        .routed($router.route) { router.destination(for: $0) }
        .skyToast($presenter.toast)
        .sheet(isPresented: Binding(
            get: { router.isAdding || router.editing != nil },
            set: { if !$0 { presenter.cancelEditing() } }
        )) {
            PlaceEditorSheet(presenter: presenter)
        }
        .sheet(item: Binding(
            get: { router.deletionTarget.map { DeletionSheetPayload(impact: $0) } },
            set: { if $0 == nil { router.deletionTarget = nil } }
        )) { payload in
            DeletionConsequencesSheet(impact: payload.impact) { strategy in
                presenter.performDelete(payload.impact, strategy: strategy)
            }
        }
    }

    // MARK: - Add section

    private var addSection: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Add a place",
                              subtitle: "Conditions are fetched per place and time zone")

                SkyButton(
                    title: presenter.isResolvingLocation ? "Getting location…" : "Use Current Location",
                    icon: "location.fill",
                    kind: .secondary,
                    isLoading: presenter.isResolvingLocation,
                    action: presenter.useCurrentLocation
                )

                if presenter.locationAuthorization.isDenied {
                    WarningBanner(
                        level: .info,
                        title: "Location access is off",
                        message: presenter.locationAuthorization.explanation + " Searching by name below works exactly the same."
                    )
                } else if let error = presenter.locationError {
                    WarningBanner(level: .warning, title: "Could not get a location",
                                  message: error + " You can still search or enter coordinates manually.")
                }

                HStack(spacing: SkySpacing.s) {
                    Image(systemName: "magnifyingglass").foregroundColor(SkyPalette.textTertiary)
                    TextField("Search a city or district", text: $presenter.searchQuery)
                        .foregroundColor(SkyPalette.textPrimary)
                        .font(SkyFont.body(15))
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .onChange(of: presenter.searchQuery) { presenter.search($0) }
                    if presenter.isSearching {
                        ProgressView().scaleEffect(0.7)
                    } else if !presenter.searchQuery.isEmpty {
                        Button(action: presenter.clearSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(SkyPalette.textTertiary)
                        }
                    }
                }
                .padding(SkySpacing.m)
                .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                    .fill(SkyPalette.surfaceSunken))

                if let error = presenter.searchError {
                    Text(error).font(SkyFont.micro(11)).foregroundColor(SkyPalette.warning)
                }

                ForEach(presenter.searchResults) { result in
                    Button { presenter.selectSearchResult(result) } label: {
                        HStack(spacing: SkySpacing.s) {
                            Image(systemName: "mappin.circle.fill").foregroundColor(SkyPalette.azure)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.name)
                                    .font(SkyFont.caption(14).weight(.medium))
                                    .foregroundColor(SkyPalette.textPrimary)
                                Text("\(result.subtitle) · \(result.timeZoneIdentifier)")
                                    .font(SkyFont.micro(10))
                                    .foregroundColor(SkyPalette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "plus.circle").foregroundColor(SkyPalette.azure)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(SkyPressStyle())
                }

                if !presenter.searchResults.isEmpty {
                    SourceStamp(source: "Open-Meteo Geocoding", updatedAt: Date(), confidence: .high, compact: true)
                }

                Button(action: presenter.startAdding) {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                        Text("Or enter a place manually")
                            .font(SkyFont.caption(13).weight(.semibold))
                    }
                    .foregroundColor(SkyPalette.azure)
                }
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "mappin.and.ellipse",
            title: "No places saved",
            message: "Every forecast in CloudCrown belongs to a specific place with its own coordinates and time zone. Days from different places are never mixed together.",
            firstStepHint: "Use your current location, or search for the area you actually go to."
        )
    }

    // MARK: - Lists

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            if !presenter.active.isEmpty {
                SectionHeader(title: "Saved Places", subtitle: "\(presenter.active.count) active")
                ForEach(presenter.active) { place in
                    placeCard(place)
                }
            }
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        if !presenter.archived.isEmpty {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                Button { withAnimation { router.showsArchived.toggle() } } label: {
                    HStack {
                        Text("Archived (\(presenter.archived.count))")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textSecondary)
                        Spacer()
                        Image(systemName: router.showsArchived ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(SkyPalette.textTertiary)
                    }
                }
                if router.showsArchived {
                    ForEach(presenter.archived) { place in placeCard(place) }
                }
            }
        }
    }

    private func placeCard(_ place: Place) -> some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: SkySpacing.m) {
                    ZStack {
                        Circle().fill(SkyPalette.azure.opacity(0.13)).frame(width: 38, height: 38)
                        Image(systemName: place.source.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SkyPalette.azure)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(place.name)
                                .font(SkyFont.headline(16))
                                .foregroundColor(SkyPalette.textPrimary)
                                .lineLimit(1)
                            if place.isDefault {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(SkyPalette.gold)
                            }
                        }
                        Text(place.timeZoneIdentifier)
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if place.isArchived {
                        SkyChip(title: "Archived", icon: "archivebox.fill", color: SkyPalette.textTertiary)
                    }
                }

                if !place.note.isEmpty {
                    Text(place.note)
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: SkySpacing.s) {
                    SkyChip(title: place.coordinateSummary(precision: presenter.settings.locationPrecision),
                            icon: "location", color: SkyPalette.lightBlue)
                    SkyChip(title: place.source.title, icon: place.source.icon, color: SkyPalette.textSecondary)
                }

                let plans = presenter.planCount(for: place)
                if plans > 0 {
                    Text("\(plans) active plan\(plans == 1 ? "" : "s") use this place.")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.textTertiary)
                }

                if let snapshot = presenter.snapshot(for: place) {
                    Button { presenter.openConditions(place) } label: {
                        HStack(spacing: 5) {
                            SourceStamp(source: snapshot.sourceSummary,
                                        updatedAt: snapshot.capturedAt,
                                        confidence: .high,
                                        isStale: snapshot.isStale,
                                        compact: true)
                            Spacer()
                            Text("View conditions")
                                .font(SkyFont.micro(11).weight(.semibold))
                                .foregroundColor(SkyPalette.azure)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(SkyPalette.azure)
                        }
                    }
                } else {
                    Text("No conditions stored for this place yet.")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.textTertiary)
                }

                Divider().background(SkyPalette.divider)

                HStack(spacing: SkySpacing.l) {
                    Button { presenter.startEditing(place) } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(SkyFont.micro(12).weight(.semibold))
                            .foregroundColor(SkyPalette.azure)
                    }
                    if !place.isDefault && !place.isArchived {
                        Button { presenter.setDefault(place) } label: {
                            Label("Set default", systemImage: "crown")
                                .font(SkyFont.micro(12).weight(.semibold))
                                .foregroundColor(SkyPalette.gold)
                        }
                    }
                    if place.isArchived {
                        Button { presenter.restore(place) } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                                .font(SkyFont.micro(12).weight(.semibold))
                                .foregroundColor(SkyPalette.success)
                        }
                    } else {
                        Button { presenter.archive(place) } label: {
                            Label("Archive", systemImage: "archivebox")
                                .font(SkyFont.micro(12).weight(.semibold))
                                .foregroundColor(SkyPalette.textSecondary)
                        }
                    }
                    Spacer()
                    Button { presenter.requestDelete(place) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SkyPalette.danger)
                    }
                }
            }
        }
    }
}

// MARK: - Editor

struct PlaceEditorSheet: View {

    @ObservedObject var presenter: PlaceLibraryPresenter

    private var draft: Binding<Place> {
        Binding(
            get: { presenter.editorDraft ?? Place(name: "", latitude: 0, longitude: 0) },
            set: { presenter.editorDraft = $0 }
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        CloudCard {
                            VStack(alignment: .leading, spacing: SkySpacing.m) {
                                field("Name", "Home, Riverside park, Office…", draft.name)
                                field("Note (optional)", "What this place is for", draft.note)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Coordinates")
                                        .font(SkyFont.micro(11).weight(.semibold))
                                        .foregroundColor(SkyPalette.textTertiary)
                                    HStack(spacing: SkySpacing.s) {
                                        coordinateField("Latitude", draft.latitude)
                                        coordinateField("Longitude", draft.longitude)
                                    }
                                    Text("You can save an approximate area rather than an exact spot — the forecast is area-based anyway.")
                                        .font(SkyFont.micro(10))
                                        .foregroundColor(SkyPalette.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Time zone")
                                        .font(SkyFont.micro(11).weight(.semibold))
                                        .foregroundColor(SkyPalette.textTertiary)
                                    TextField("Region/City", text: draft.timeZoneIdentifier)
                                        .foregroundColor(SkyPalette.textPrimary)
                                        .font(SkyFont.body(14))
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .padding(SkySpacing.m)
                                        .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                            .fill(SkyPalette.surfaceSunken))
                                    if TimeZone(identifier: draft.wrappedValue.timeZoneIdentifier) == nil {
                                        Text("Unknown time zone identifier — times would be wrong. Use a value like Europe/Berlin.")
                                            .font(SkyFont.micro(10))
                                            .foregroundColor(SkyPalette.danger)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }

                                Toggle(isOn: draft.isDefault) {
                                    Text("Set as default place")
                                        .font(SkyFont.caption(13).weight(.medium))
                                        .foregroundColor(SkyPalette.textPrimary)
                                }
                                .tint(SkyPalette.gold)
                            }
                        }

                        if let message = presenter.saveError {
                            SaveErrorBanner(message: message,
                                            onRetry: presenter.save,
                                            onDismiss: presenter.dismissSaveError)
                        }

                        ForEach(presenter.draftValidationMessages, id: \.self) { message in
                            WarningBanner(level: .danger, title: "Cannot save yet", message: message)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill").font(.system(size: 11))
                            Text("Coordinates are sent to the forecast service at your chosen precision: \(presenter.settings.locationPrecision.title).")
                                .font(SkyFont.micro(11))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundColor(SkyPalette.textTertiary)

                        Spacer(minLength: 80)
                    }
                    .padding(SkySpacing.l)
                }

                VStack {
                    Spacer()
                    SkyButton(title: "Save Place", icon: "checkmark", kind: .primary,
                              isLoading: presenter.isSaving,
                              isEnabled: presenter.canSaveDraft,
                              action: presenter.save)
                        .padding(.horizontal, SkySpacing.l)
                        .padding(.vertical, SkySpacing.l)
                        .background(
                            LinearGradient(colors: [SkyPalette.cloudWhite.opacity(0), SkyPalette.cloudWhite],
                                           startPoint: .top, endPoint: .bottom)
                                .ignoresSafeArea()
                        )
                }
            }
            .navigationTitle("Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presenter.cancelEditing() }
                        .foregroundColor(SkyPalette.textSecondary)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func field(_ title: String, _ placeholder: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
            TextField(placeholder, text: binding)
                .foregroundColor(SkyPalette.textPrimary)
                .font(SkyFont.body(15))
                .padding(SkySpacing.m)
                .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                    .fill(SkyPalette.surfaceSunken))
        }
    }

    private func coordinateField(_ title: String, _ binding: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(SkyFont.micro(10)).foregroundColor(SkyPalette.textTertiary)
            TextField("0.0000", text: Binding(
                get: { String(format: "%.4f", binding.wrappedValue) },
                set: { binding.wrappedValue = Double($0.replacingOccurrences(of: ",", with: ".")) ?? binding.wrappedValue }
            ))
            .font(SkyFont.metric(15))
            .keyboardType(.numbersAndPunctuation)
            .padding(SkySpacing.s)
            .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                .fill(SkyPalette.surfaceSunken))
        }
        .frame(maxWidth: .infinity)
    }
}
