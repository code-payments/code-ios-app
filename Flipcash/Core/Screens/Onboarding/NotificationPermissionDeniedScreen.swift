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
    @State private var toggleOn = false

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
                    DeviceTogglePreview(toggleOn: $toggleOn)
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
        .task {
            try? await Task.sleep(for: .seconds(0.35))
            toggleOn = true
        }
    }
}

// MARK: - Device Toggle Preview -

private struct DeviceTogglePreview: View {
    @Binding var toggleOn: Bool

    var body: some View {
        Image(.deviceFrame)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 300)
            .overlay(alignment: .top) {
                NotificationToggleRow(isOn: $toggleOn)
                    .offset(y: 70)
            }
    }
}

// MARK: - Notification Toggle Row -

private struct NotificationToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Allow Notifications", isOn: $isOn)
            .tint(.green)
            .font(.system(size: 14, weight: .medium))
            .allowsHitTesting(false)
            .padding(12)
            .modifier(NotificationToggleBackground())
    }
}

// MARK: - Notification Toggle Background -

private struct NotificationToggleBackground: ViewModifier {
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
    NotificationPermissionDeniedScreen(viewModel: OnboardingViewModel(container: .mock))
}
