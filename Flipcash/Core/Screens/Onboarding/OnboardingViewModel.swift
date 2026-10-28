//
//  OnboardingViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-05-05.
//

import SwiftUI
import FlipcashUI
import FlipcashCore
import UserNotifications

@Observable
class OnboardingViewModel {

    var path: [OnboardingPath] = []

    var accessKeyButtonState: ButtonState = .normal

    var dialogItem: DialogItem?

    private(set) var inflightMnemonic: MnemonicPhrase = .generate(.words12)

    @ObservationIgnored private let container: Container
    @ObservationIgnored private let sessionAuthenticator: SessionAuthenticator
    @ObservationIgnored private var initializedAccount: InitializedAccount?
    @ObservationIgnored private let pushStatus: () async -> UNAuthorizationStatus
    @ObservationIgnored private let hasDisplayName: (InitializedAccount) async -> Bool?
    @ObservationIgnored private let finishLogin: (InitializedAccount) -> Void

    /// Built on first call to ``navigateToDisplayName``; the display-name step
    /// runs pre-login, so it owns its submission against the in-flight owner.
    var nameViewModel: OnboardingNameViewModel?

    // MARK: - Init -

    /// The closures are seams for tests; the defaults read the real notification status and
    /// profile, and open the session.
    ///
    /// - Parameters:
    ///   - pushStatus: the current notification authorization.
    ///   - hasDisplayName: whether the account's profile already has a display name, or `nil`
    ///     when that can't be determined.
    ///   - finishLogin: opens the session once onboarding is done.
    init(
        container: Container,
        pushStatus: @escaping () async -> UNAuthorizationStatus = { await PushController.fetchStatus() },
        hasDisplayName: ((InitializedAccount) async -> Bool?)? = nil,
        finishLogin: ((InitializedAccount) -> Void)? = nil
    ) {
        self.container            = container
        self.sessionAuthenticator = container.sessionAuthenticator
        self.pushStatus           = pushStatus
        self.hasDisplayName       = hasDisplayName ?? { [flipClient = container.flipClient, accountManager = container.accountManager] account in
            await Self.lookUpDisplayName(for: account, flipClient: flipClient, accountManager: accountManager)
        }
        self.finishLogin          = finishLogin ?? { [authenticator = container.sessionAuthenticator] account in
            authenticator.completeLogin(with: account)
        }
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
        nameViewModel = nil

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

        // Every new account needs a display name for tips and chat, so collect
        // one now — before the push-permission prompt. (Phone verification is
        // no longer part of onboarding; a phone can still be connected later.)
        navigateToDisplayName()

        try await Task.delay(milliseconds: 500) // Delay deferred state change
    }

    /// Advances past the display-name step: requests push permission when
    /// undetermined, otherwise finishes login. Contacts access is requested
    /// later, in-app.
    private func advanceFromNameStep() async {
        let pushStatus = await pushStatus()
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
                sessionAuthenticator.beginOnboarding(with: initializedAccount)
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

        OnboardingProgress.setCompleted(true, owner: initializedAccount.keyAccount.ownerPublicKey)
        finishLogin(initializedAccount)

        Analytics.onboardingCompleted()
    }

    // MARK: - Resume -

    /// Runs the onboarding steps still owed by an account that is already signed in: a launch
    /// after a kill mid-onboarding, or an interactive login (seed entry, account picker, deep
    /// link). Asks for a display name only when the profile has none, then applies the same
    /// push rule as a new account, so already-decided permissions finish straight away.
    func resumeOnboarding(with account: InitializedAccount) async {
        initializedAccount = account
        nameViewModel = nil

        let named = await hasDisplayName(account)
        guard named == false else {
            await advanceFromNameStep()
            return
        }

        navigateToDisplayName(owner: account.keyAccount.owner)
    }

    private static func lookUpDisplayName(
        for account: InitializedAccount,
        flipClient: FlipClient,
        accountManager: AccountManager
    ) async -> Bool? {
        do {
            let profile = try await flipClient.fetchProfile(userID: account.userID, owner: account.keyAccount.owner)
            accountManager.cacheProfile(profile, ownerPublicKey: account.keyAccount.ownerPublicKey)
            return profile.displayName?.isEmpty == false
        } catch {
            // Offline: trust the name cached on the account's keychain entry, and when that
            // is blank too, skip the step rather than block the way home.
            let cached = accountManager.fetchHistorical()
                .first { $0.account.ownerPublicKey == account.keyAccount.ownerPublicKey }?
                .displayName
            return cached?.isEmpty == false ? true : nil
        }
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

    func navigateToDisplayName(owner: KeyPair? = nil) {
        if nameViewModel == nil {
            let vm = OnboardingNameViewModel(
                owner: owner ?? inflightMnemonic.solanaKeyPair(),
                flipClient: container.flipClient,
            )
            vm.onComplete = { [weak self] in
                Task { await self?.advanceFromNameStep() }
            }
            nameViewModel = vm
        }
        path.append(.displayName)
    }

}

// MARK: - Path -

nonisolated enum OnboardingPath {
    case accountSelection
    case login
    case accessKey
    case accessKeyHelp
    case displayName
    case pushNotifications
    case pushNotificationsDenied
}
