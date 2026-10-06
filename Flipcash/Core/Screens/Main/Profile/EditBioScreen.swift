//
//  EditBioScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Editing the bio on its own, pushed from Edit Profile.
struct EditBioScreen: View {

    @Environment(AppRouter.self) private var router

    @State private var model: EditBioModel
    @State private var dialog: DialogItem?
    @State private var saveTask: Task<Void, Never>?

    @FocusState private var isFocused: Bool

    /// Takes the model rather than building it, so the field opens on the bio it is about to
    /// replace instead of animating it in over the push.
    init(model: EditBioModel) {
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
                TextField("Add a bio", text: $model.text, axis: .vertical)
                    .font(.appDisplayXS)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(3...8)
                    .focused($isFocused)
                    .disabled(model.state != .normal)
                    .accessibilityIdentifier("edit-bio-field")
                    .padding(.top, 20)

                Text("\(model.remaining)")
                    .font(.appTextSmall)
                    .foregroundStyle(model.remaining < 0 ? Color.textError : Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)
                    .accessibilityIdentifier("edit-bio-counter")

                if let fieldError = model.fieldError {
                    Text(fieldError.message)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textError)
                        .padding(.top, 8)
                        .accessibilityIdentifier("edit-bio-error")
                }

                Spacer()

                Button(action: save) {
                    ButtonStateLabel("Save", state: buttonState)
                }
                .buttonStyle(.filled)
                .disabled(!model.canSave)
                .accessibilityIdentifier("edit-bio-save")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Bio")
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $dialog)
        .focusAfterPush($isFocused)
        .onChange(of: model.failure == nil) { _, isNil in
            guard !isNil else { return }
            model.failure = nil
            dialog = .error(title: "Couldn't Save Your Bio", subtitle: "Try again")
        }
        // Leaving the screen abandons the submission: its only continuation is a pop.
        .onDisappear { saveTask?.cancel() }
    }

    private func save() {
        guard saveTask == nil else { return }
        isFocused = false
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
