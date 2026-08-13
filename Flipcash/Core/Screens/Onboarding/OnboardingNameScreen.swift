//
//  OnboardingNameScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The onboarding display-name step, entered after the access key. It is
/// mandatory — the surrounding `navigationDestination` hides the back button —
/// so the account always has a name for tips and chat before reaching the app.
struct OnboardingNameScreen: View {

    @Bindable private var viewModel: OnboardingNameViewModel

    @FocusState private var isNameFocused: Bool

    /// Shown only once the limit is close enough to explain a disabled Next.
    private static let countdownThreshold = 10

    // MARK: - Init -

    init(viewModel: OnboardingNameViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("What is your name?")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                TextField("Your Name", text: $viewModel.displayName)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                    .focused($isNameFocused)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .onSubmit(viewModel.submit)
                    .padding(.top, 32)
                    .disabled(viewModel.isSubmitting)

                Text("This is how you'll appear to others")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 8)

                Spacer()

                if viewModel.remainingCharacters < Self.countdownThreshold {
                    Text("\(viewModel.remainingCharacters) characters")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                }

                Button(action: viewModel.submit) {
                    if viewModel.isSubmitting {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Text("Next")
                    }
                }
                .buttonStyle(.filled)
                .disabled(viewModel.validatedDisplayName == nil || viewModel.isSubmitting)
                .accessibilityIdentifier("onboarding-name-next-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
        .onAppear { isNameFocused = true }
    }
}

// MARK: - Previews -

#Preview {
    NavigationStack {
        OnboardingNameScreen(
            viewModel: OnboardingNameViewModel(owner: .mock, flipClient: .mock)
        )
    }
    .injectingEnvironment(from: .mock)
}
