//
//  OnboardingEmailScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The Group Money onboarding email step (frame 2-05). The address is linked without a
/// verification code, so there is no code step after it.
///
/// Not ``EnterEmailScreen``: that screen is bound to the on-ramp's verification flow (code,
/// resend, deep link), none of which applies here.
struct OnboardingEmailScreen: View {

    @Bindable private var viewModel: OnboardingEmailViewModel

    @FocusState private var isFocused: Bool

    // MARK: - Init -

    init(viewModel: OnboardingEmailViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 15) {
                OnboardingStepHeader(text: StepHeaderText(
                    title: "Your email",
                    subtitle: "Add an email address to your account."
                ))
                .padding(.bottom, 10)

                OnboardingFieldLabel(title: "Email")

                InputContainer(size: .regular) {
                    // Autocorrection stays on, as on EnterEmailScreen: turning it off hides the
                    // QuickType bar, where iOS offers the contact card's address. It stays enabled
                    // while submitting: a disabled field resigns, which takes the keyboard down
                    // before the name step pushes in.
                    TextField("Email", text: $viewModel.enteredEmail)
                        .font(.appTextXL)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.next)
                        .onSubmit(viewModel.submit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .multilineTextAlignment(.leading)
                        .padding([.leading, .trailing], 15)
                        .focused($isFocused)
                }

                Spacer()

                Button(action: viewModel.submit) {
                    ButtonStateLabel("Next", state: viewModel.buttonState)
                }
                .buttonStyle(.filled)
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("onboarding-email-next-button")
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
        .focusAfterPush($isFocused)
    }
}

// MARK: - Previews -

#Preview {
    NavigationStack {
        OnboardingEmailScreen(
            viewModel: OnboardingEmailViewModel(owner: .mock) { _, _ in }
        )
    }
    .injectingEnvironment(from: .mock)
}
