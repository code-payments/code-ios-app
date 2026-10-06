//
//  EditFeaturedGroupsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Choosing the public groups the profile features, pushed from Edit Profile.
struct EditFeaturedGroupsScreen: View {

    @Environment(AppRouter.self) private var router

    @State private var model: EditFeaturedGroupsModel
    @State private var dialog: DialogItem?
    @State private var saveTask: Task<Void, Never>?

    /// Takes the model rather than building it, so the list opens on the groups featured now.
    init(model: EditFeaturedGroupsModel) {
        _model = State(initialValue: model)
    }

    private var buttonState: ButtonState {
        switch model.state {
        case .normal: .normal
        case .saving: .loading
        case .saved:  .success
        }
    }

    var body: some View {
        @Bindable var model = model

        Background(color: .backgroundMain) {
            list
                // Rows scroll under Save but are blurred out there, not left readable.
                .hardScrollEdge(for: .bottom)
                .scrollEdgeBar(.bottom) {
                    Button(action: save) {
                        ButtonStateLabel("Save", state: buttonState)
                    }
                    .buttonStyle(.filled)
                    // The disabled fill is translucent; without this the rows show through it.
                    .background(Color.backgroundMain, in: RoundedRectangle(cornerRadius: Metrics.buttonRadius))
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("edit-featured-groups-save")
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
        }
        .navigationTitle("Favorite Groups")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $model.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search your public groups"
        )
        .dialog(item: $dialog)
        .task { await model.loadCandidates() }
        .onChange(of: model.failure) { _, failure in
            guard let failure else { return }
            model.failure = nil
            switch failure {
            case .privateGroup:
                dialog = .error(title: "Only Public Groups Can Be Featured", subtitle: "One of these groups is private. Remove it and try again")
            case .other:
                dialog = .error(title: "Couldn't Save Your Groups", subtitle: "Try again")
            }
        }
        // Leaving the screen abandons the submission: its only continuation is a pop.
        .onDisappear { saveTask?.cancel() }
    }

    private var list: some View {
        List {
            Section {
                // The list appears whole once the feed is read, rather than growing from the
                // featured groups. The List itself stays so the search field keeps its place.
                if model.loadState != .loading {
                    ForEach(model.visibleCandidates) { group in
                        row(group)
                    }
                }
            } header: {
                ListHeader("\(model.selection.count) of \(FeaturedGroups.limit) selected")
            } footer: {
                if model.loadState != .loading, !model.candidates.isEmpty {
                    Text("These public groups will appear on your public profile")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        }
        .listStyle(.grouped)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.loadState == .loading {
                ProgressView()
                    .tint(Color.textSecondary)
            } else {
                emptyState
            }
        }
    }

    private func row(_ group: Conversation) -> some View {
        Button {
            model.toggle(group.id)
        } label: {
            FeaturedGroupRow(group: group) {
                CheckView(active: model.isSelected(group.id))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(model.canToggle(group.id) ? 1 : 0.4)
        .disabled(!model.canToggle(group.id))
        .listRowBackground(Color.backgroundMain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(group.featuredRowAccessibilityLabel))
        .accessibilityAddTraits(model.isSelected(group.id) ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("edit-featured-groups-row")
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.query.isEmpty, model.visibleCandidates.isEmpty {
            SearchResultsUnavailableView(searchText: model.query)
        } else if model.loadState == .failed {
            Text("Couldn't load your groups")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
        } else if model.loadState == .loaded, model.candidates.isEmpty {
            Text("Join a public group to feature it on your profile")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func save() {
        guard saveTask == nil else { return }
        saveTask = Task {
            await model.save()
            if model.state == .saved {
                // Same beat the other editors hold their checkmark for.
                try? await Task.delay(milliseconds: 500)
                guard !Task.isCancelled else { return }
                router.popTopmost()
            }
            saveTask = nil
        }
    }
}
