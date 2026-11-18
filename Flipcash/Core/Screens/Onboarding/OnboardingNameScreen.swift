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

    private let copy: OnboardingNameCopy

    // MARK: - Init -

    init(viewModel: OnboardingNameViewModel, copy: OnboardingNameCopy = .standard) {
        self.viewModel = viewModel
        self.copy = copy
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            switch copy {
            case .standard:
                VStack(alignment: .leading, spacing: 0) {
                    Text(copy.title)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .padding(.top, 20)

                    nameField
                        .padding(.top, 32)

                    Text(copy.hint)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 8)

                    Spacer()

                    nextControls
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .groupMoney:
                // The hint sits under the title, as in the other Group Money steps.
                OnboardingStepLayout(header: StepHeaderText(title: copy.title, subtitle: copy.hint)) {
                    nameField
                } action: {
                    nextControls
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
        .focusAfterPush($isNameFocused)
    }

    // MARK: - Subviews -

    private var nameField: some View {
        TextField("Your Name", text: $viewModel.displayName)
            .font(.appDisplayMedium)
            .foregroundStyle(Color.textMain)
            .focused($isNameFocused)
            .textContentType(.name)
            .submitLabel(.next)
            .onSubmit(viewModel.submit)
            .disabled(viewModel.isSubmitting)
    }

    private var nextControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.remainingCharacters < Self.countdownThreshold {
                Text("\(viewModel.remainingCharacters) characters")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
            }

            Button(action: viewModel.submit) {
                ButtonStateLabel("Next", state: viewModel.buttonState)
            }
            .buttonStyle(.filled)
            .disabled(viewModel.validatedDisplayName == nil || viewModel.isSubmitting)
            .accessibilityIdentifier("onboarding-name-next-button")
        }
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

// MARK: - Copy -

/// The words on ``OnboardingNameScreen``. ``standard`` is today's flow; ``groupMoney`` is the
/// Group Money new-account flow (frame 2-06).
enum OnboardingNameCopy: Equatable {
    case standard
    case groupMoney

    var title: String {
        switch self {
        case .standard:   "What's your name?"
        case .groupMoney: "Your name"
        }
    }

    var hint: String {
        switch self {
        case .standard:   "This is how you'll appear to others"
        case .groupMoney: "This is how you'll appear in your groups."
        }
    }
}
