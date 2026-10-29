//
//  EditGroupBalanceRequirementScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Replacing a group's join or chat minimum, pushed from a row of Edit Group's Balance
/// Requirements. Entered on ``EnterAmountView`` like Minimum To Chat and the creation form's
/// custom requirement.
struct EditGroupBalanceRequirementScreen: View {

    @Environment(AppRouter.self) private var router

    @State private var model: EditGroupBalanceRequirementModel
    @State private var dialog: DialogItem?
    @State private var saveTask: Task<Void, Never>?

    /// Takes the model rather than building it, so the field opens on the amount it is about to
    /// replace instead of animating it in over the push.
    init(model: EditGroupBalanceRequirementModel) {
        _model = State(initialValue: model)
    }

    private var buttonState: ButtonState {
        switch model.state {
        case .normal: .normal
        case .saving: .loading
        case .saved:  .success
        }
    }

    private var field: DialogItem.GroupField {
        switch model.role {
        case .join: .joinRequirement
        case .chat: .chatRequirement
        }
    }

    private var hint: String {
        switch model.role {
        case .join: "People won't be able to join this group if their balance is less than this amount"
        case .chat: "People won't be able to send messages in this group if their balance is less than this amount"
        }
    }

    var body: some View {
        @Bindable var model = model

        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .balanceRequirement,
                enteredAmount: $model.enteredAmount,
                subtitle: .hidden,
                actionState: .constant(buttonState),
                actionEnabled: { _ in model.canSave && saveTask == nil },
                action: submit,
                actionTitle: "Save",
                header: AnyView(EnterAmountHeader(
                    enteredAmount: $model.enteredAmount,
                    hint: .description(hint)
                ))
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle(field.title)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if model.canRemove {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Remove", action: proposeRemove)
                        .disabled(saveTask != nil)
                }
            }
        }
        .dialog(item: $dialog)
        .onChange(of: model.failure) { _, failure in
            guard let failure else { return }
            model.failure = nil
            dialog = Self.dialog(for: failure)
        }
        // Leaving the screen abandons the submission: its only continuation is a pop.
        .onDisappear { saveTask?.cancel() }
    }

    static func dialog(for failure: EditGroupBalanceRequirementModel.Failure) -> DialogItem {
        switch failure {
        case .chatNotAboveJoin(let join):
            .error(
                title: "Chat Minimum Too Low",
                subtitle: "The chat minimum must be more than the join minimum of \(join.formatted())"
            )
        case .invalidRules:
            .error(title: "This Requirement Isn't Valid", subtitle: "Try a different minimum balance")
        case .rulesNotSatisfied:
            .error(title: "You Don't Meet This Requirement", subtitle: "Lower the minimum balance or add funds")
        case .failed:
            .error(title: "Couldn't Save the Requirement", subtitle: "Try again")
        }
    }

    /// Save proposes; the dialog commits, since the requirement changes for everyone in the group.
    /// An entry the server would refuse is stopped here, before the confirmation.
    private func submit() {
        guard model.canSave, saveTask == nil else { return }
        if let blocker = model.blocker {
            dialog = Self.dialog(for: blocker)
            return
        }
        dialog = .confirmGroupChange(field) { save(model.save) }
    }

    private func proposeRemove() {
        guard model.canRemove, saveTask == nil else { return }
        dialog = .confirmGroupChange(field) { save(model.remove) }
    }

    private func save(_ operation: @escaping () async -> Void) {
        guard saveTask == nil else { return }
        saveTask = Task {
            await operation()
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
