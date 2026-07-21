//
//  OnboardingViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-05-05.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@Observable
class OnboardingViewModel {

    var path: [OnboardingPath] = []

    var accessKeyButtonState: ButtonState = .normal

    var dialogItem: DialogItem?

    private(set) var inflightMnemonic: MnemonicPhrase = .generate(.words12)

    @ObservationIgnored private let container: Container
    @ObservationIgnored private let sessionAuthenticator: SessionAuthenticator
    @ObservationIgnored private var initializedAccount: InitializedAccount?

    /// Built on first call to ``navigateToPhoneVerification``; shared
    /// between the `EnterPhoneScreen` and `ConfirmPhoneScreen`
    /// destinations so input state survives the push.
    var phoneVerificationViewModel: PhoneVerificationViewModel?

    // MARK: - Init -

    init(container: Container) {
        self.container            = container
        self.sessionAuthenticator = container.sessionAuthenticator
    }

    // MARK: - Action -

    func loginAction() {
        let hasAccounts = !sessionAuthenticator.accountManager
            .fetchActiveHistorical()
            .isEmpty

        if hasAccounts {
            navigateToAccountSelection()
        } else {
            navigateToLogin()
        }
    }

    func createAccountAction() {
        inflightMnemonic = MnemonicPhrase.generate(.words12)
        phoneVerificationViewModel = nil

        navigateToAccessKey()

        Analytics.buttonTapped(name: .createAccount)
    }

    func saveToPhotosAction() {
        Task {
            accessKeyButtonState = .loading

            let mnemonic = inflightMnemonic
            do {
                try await PhotoLibrary.saveSecretRecoveryPhraseSnapshot(for: mnemonic)
            } catch {
                accessKeyButtonState = .normal
                dialogItem = .error(
                    title: "Failed to Save",
                    subtitle: "Please allow Flipcash access to Photos in Settings in order to save your Access Key."
                ) {
                    .destructive("Open Settings") {
                        URL.openSettings()
                    };
                    .notNow()
                }
                return
            }

            do {
                try await completeAccountCreation()
            } catch {
                showAccountCreationError()
            }
        }

        Analytics.buttonTapped(name: .saveAccessKey)
    }

    func wroteDownAction() {
        dialogItem = .alert(
            title: "Are You Sure?",
            subtitle: "These 12 words are the only way to recover your Flipcash account. Make sure you wrote them down, and keep them private and safe."
        ) {
            .destructive("Yes, I Wrote Them Down") { [weak self] in
                Task {
                    do {
                        try await self?.completeAccountCreation()
                    } catch {
                        self?.showAccountCreationError()
                    }
                }

                Analytics.buttonTapped(name: .wroteAccessKey)
            };
            .cancel()
        }
    }

    private func completeAccountCreation() async throws {
        accessKeyButtonState = .loading
        defer {
            accessKeyButtonState = .normal
        }

        try await registerAccount(mnemonic: inflightMnemonic)

        try await Task.delay(milliseconds: 150)
        accessKeyButtonState = .success
        try await Task.delay(milliseconds: 500)

        // Phone verification only exists to power Send; show it when Send is
        // available for this account, otherwise advance straight to the next step.
        if await shouldOfferPhoneVerification() {
            navigateToPhoneVerification()
        } else {
            await advanceFromPhoneVerificationStep()
        }

        try await Task.delay(milliseconds: 500) // Delay deferred state change
    }

    /// Whether to collect a phone number during onboarding, decided by the
    /// server's `enablePhoneNumberSend`. The fetch is time-boxed so a slow connection can't stall onboarding;
    /// the step is skipped if the account isn't known yet, the fetch times out, or
    /// it fails — a phone can still be connected later from the Send sheet.
    private func shouldOfferPhoneVerification() async -> Bool {
        guard let userID = initializedAccount?.userID else {
            return false
        }

        let flags = try? await container.flipClient.fetchUserFlags(
            userID: userID,
            owner: inflightMnemonic.solanaKeyPair(),
            timeout: 5
        )

        return flags?.enablePhoneNumberSend == true
    }

    /// Advances past the phone step: requests push permission when undetermined,
    /// otherwise finishes login. Contacts access is requested later, from Send.
    private func advanceFromPhoneVerificationStep() async {
        let pushStatus = await PushController.fetchStatus()
        switch pushStatus {
        case .notDetermined:
            navigateToPushNotifications()
        case .authorized, .provisional, .denied, .ephemeral:
            completeOnboardingAndLogin()
        @unknown default:
            navigateToPushNotifications()
        }
    }

    private func showAccountCreationError() {
        dialogItem = .error(
            title: "Something Went Wrong",
            subtitle: "We couldn't create your account. Please try again."
        )
    }

    func recoverExistingAccount(accountDescription: AccountDescription) {
        Task {
            do {
                let initializedAccount = try await sessionAuthenticator.initialize(
                    using: accountDescription.account.mnemonic,
                    isRegistration: false
                )

                try await Task.delay(milliseconds: 500)
                sessionAuthenticator.completeLogin(with: initializedAccount)
            } catch {
                // Login failed silently
            }
        }
    }

    func allowPushNotificationsAction() {
        Task {
            do {
                let granted = try await PushController.authorizeAndRegister()
                if granted {
                    completeOnboardingAndLogin()
                } else {
                    navigateToPushNotificationsDenied()
                }
            } catch {
                completeOnboardingAndLogin()
            }
        }

        Analytics.buttonTapped(name: .allowPush)
    }

    func skipPushNotificationsAction() {
        dialogItem = .alert(
            title: "Are You Sure?",
            subtitle: "You won't receive updates when your balance changes"
        ) {
            .destructive("OK Allow") { [weak self] in
                Task {
                    _ = try? await PushController.authorizeAndRegister()
                    self?.completeOnboardingAndLogin()
                }

                Analytics.buttonTapped(name: .allowPush)
            };
            .subtle("I'm Sure") { [weak self] in
                self?.completeOnboardingAndLogin()

                Analytics.buttonTapped(name: .skipPush)
            }
        }
    }

    func openNotificationSettingsAction() {
        completeOnboardingAndLogin()
        URL.openSettings()
    }

    func confirmSkipNotificationsAction() {
        completeOnboardingAndLogin()

        Analytics.buttonTapped(name: .skipPush)
    }

    // MARK: - Registration -

    private func registerAccount(mnemonic: MnemonicPhrase) async throws {
        let owner = mnemonic.solanaKeyPair()

        Analytics.createAccount(owner: owner.publicKey)

        let account = try await sessionAuthenticator.initialize(
            using: mnemonic,
            isRegistration: true
        )

        initializedAccount = account
    }

    // MARK: - Account Creation -

    private func completeOnboardingAndLogin() {
        guard let initializedAccount else {
            return
        }

        sessionAuthenticator.completeLogin(with: initializedAccount)

        Analytics.track(event: Analytics.GeneralEvent.completeOnboarding)
    }

    // MARK: - Navigation -

    func navigateToRoot() {
        path = []
    }

    func navigateToAccountSelection() {
        path = [.accountSelection]
    }

    func navigateToLogin() {
        path = [.login]
    }

    func navigateToAccessKey() {
        path = [.accessKey]
    }

    func navigateToPushNotifications() {
        path.append(.pushNotifications)
    }

    func navigateToPushNotificationsDenied() {
        path.append(.pushNotificationsDenied)
    }

    func navigateToPhoneVerification() {
        if phoneVerificationViewModel == nil {
            let vm = PhoneVerificationViewModel(
                owner: inflightMnemonic.solanaKeyPair(),
                flipClient: container.flipClient,
            )
            vm.onCodeRequested = { [weak self] in
                self?.navigateToConfirmPhoneCode()
            }
            vm.onVerified = { [weak self] in
                Task { await self?.advanceFromPhoneVerificationStep() }
            }
            phoneVerificationViewModel = vm
        }
        path.append(.phoneVerification)
    }

    func navigateToConfirmPhoneCode() {
        path.append(.confirmPhoneNumberCode)
    }

}

// MARK: - Path -

nonisolated enum OnboardingPath {
    case accountSelection
    case login
    case accessKey
    case accessKeyHelp
    case phoneVerification
    case confirmPhoneNumberCode
    case pushNotifications
    case pushNotificationsDenied
}
