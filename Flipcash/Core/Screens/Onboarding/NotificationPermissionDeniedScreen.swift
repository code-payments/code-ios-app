//
//  NotificationPermissionDeniedScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Shown during onboarding only when the user denies the system notification permission prompt.
///
/// Once denied, iOS will not present the system prompt again, so this screen gives the user
/// two options:
/// - **Open Settings** — completes onboarding and deep-links to the app's Settings page
///   where notifications can be re-enabled manually.
/// - **I'm Sure** — completes onboarding without notifications.
struct NotificationPermissionDeniedScreen: View {

    @Bindable private var viewModel: OnboardingViewModel

    // MARK: - Init -

    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    Spacer()
                    Image(.notificationPreview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300)
                    Spacer()
                    Text("Are You Sure?")
                        .font(.appTitle)
                        .foregroundStyle(Color.textMain)
                    Text("You won't be notified of changes to your balance if you don't enable notifications")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    Spacer()
                }

                Spacer()

                Button("Open Settings", action: viewModel.openNotificationSettingsAction)
                    .buttonStyle(.filled)

                Button("I'm Sure", action: viewModel.confirmSkipNotificationsAction)
                    .buttonStyle(.subtle)
            }
            .padding(20)
        }
        .navigationBarBackButtonHidden(true)
    }
}
