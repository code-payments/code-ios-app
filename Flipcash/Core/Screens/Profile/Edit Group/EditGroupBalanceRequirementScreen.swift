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
        .dialog(item: $dialog)
        .onChange(of: model.failure) { _, failure in
            guard let failure else { return }
            model.failure = nil
            switch failure {
            case .unavailable:
                dialog = .info(
                    title: "Not Available Yet",
                    subtitle: "Balance requirements can't be changed yet"
                )
            case .failed:
                dialog = .error(title: "Couldn't Save the Requirement", subtitle: "Try again")
            }
        }
        // Leaving the screen abandons the submission: its only continuation is a pop.
        .onDisappear { saveTask?.cancel() }
    }

    /// Save proposes; the dialog commits, since the requirement changes for everyone in the group.
    private func submit() {
        guard model.canSave, saveTask == nil else { return }
        dialog = .confirmGroupChange(field) { save() }
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
