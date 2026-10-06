//
//  EditGroupDescriptionScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Editing a group's description on its own, pushed from Edit Group's Description card. Drawn like
/// ``EditBioScreen``; an empty description is a clear.
struct EditGroupDescriptionScreen: View {

    @Environment(AppRouter.self) private var router

    @State private var model: EditGroupDescriptionModel
    @State private var dialog: DialogItem?
    @State private var saveTask: Task<Void, Never>?

    @FocusState private var isFocused: Bool

    /// Takes the model rather than building it, so the field opens on the description it is about
    /// to replace instead of animating it in over the push.
    init(model: EditGroupDescriptionModel) {
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
            VStack(alignment: .leading, spacing: 0) {
                TextField("Add a description", text: $model.text, axis: .vertical)
                    .font(.appDisplayXS)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(3...8)
                    .focused($isFocused)
                    .disabled(model.state != .normal)
                    .accessibilityIdentifier("edit-group-description-field")
                    .padding(.top, 20)

                Text("\(model.remaining)")
                    .font(.appTextSmall)
                    .foregroundStyle(model.remaining < 0 ? Color.textError : Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)
                    .accessibilityIdentifier("edit-group-description-counter")

                if let fieldError = model.fieldError {
                    Text(fieldError.message)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textError)
                        .padding(.top, 8)
                        .accessibilityIdentifier("edit-group-description-error")
                }

                Spacer()

                Button(action: submit) {
                    ButtonStateLabel("Save", state: buttonState)
                }
                .buttonStyle(.filled)
                .disabled(!model.canSave || saveTask != nil)
                .accessibilityIdentifier("edit-group-description-save")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Description")
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $dialog)
        .focusAfterPush($isFocused)
        .onChange(of: model.failure == nil) { _, isNil in
            guard !isNil else { return }
            model.failure = nil
            dialog = .error(title: "Couldn't Save the Description", subtitle: "Try again")
        }
        // Leaving the screen abandons the submission: its only continuation is a pop.
        .onDisappear { saveTask?.cancel() }
    }

    /// Save proposes; the dialog commits, since the description changes for everyone in the group.
    private func submit() {
        guard model.canSave, saveTask == nil else { return }
        isFocused = false
        dialog = .confirmGroupChange(.description) { save() }
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
