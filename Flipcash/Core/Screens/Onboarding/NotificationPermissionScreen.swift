//
//  NotificationPermissionScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct NotificationPermissionScreen: View {

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
                    Text("Push Notifications Required")
                        .font(.appTitle)
                        .foregroundStyle(Color.textMain)
                    Text("Push notifications are used to update you on changes in your balance")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    Spacer()
                }

                Spacer()

                Button("OK", action: viewModel.allowPushNotificationsAction)
                    .buttonStyle(.filled)

                Button("Not Now", action: viewModel.skipPushNotificationsAction)
                    .buttonStyle(.subtle)
            }
            .padding(20)
        }
        .navigationBarBackButtonHidden(true)
        .dialog(item: $viewModel.dialogItem)
    }
}
