//
//  NotificationPermissionScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct NotificationPermissionScreen: View {

    @Bindable private var viewModel: OnboardingViewModel
    @State private var showNotification = false

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
                    DeviceNotificationPreview(showNotification: showNotification)
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
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.4).delay(0.3)) {
                showNotification = true
            }
        }
    }
}

// MARK: - Device Notification Preview -

private struct DeviceNotificationPreview: View {
    let showNotification: Bool

    var body: some View {
        Image(.deviceFrame)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 300)
            .overlay(alignment: .top) {
                NotificationBannerPreview()
                    .offset(y: 70)
                    .scaleEffect(showNotification ? 1 : 0)
                    .opacity(showNotification ? 1 : 0)
            }
    }
}

// MARK: - Notification Banner Preview -

private struct NotificationBannerPreview: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(.flipcashIcon)
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("You Bought $20.00")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("now")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text("$20.00 has been added to your wallet")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .modifier(NotificationBannerBackground())
    }
}

// MARK: - Notification Banner Background -

private struct NotificationBannerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - Previews -

#Preview {
    NotificationPermissionScreen(viewModel: OnboardingViewModel(container: .mock))
}
