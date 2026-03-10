//
//  OnboardingViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-05-05.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@MainActor
class OnboardingViewModel: ObservableObject {

    @Published var path: [OnboardingPath] = []

    @Published var accessKeyButtonState: ButtonState = .normal

    @Published var dialogItem: DialogItem?

    private(set) var inflightMnemonic: MnemonicPhrase = .generate(.words12)

    private let container: Container
    private let flipClient: FlipClient
    private let sessionAuthenticator: SessionAuthenticator
    private let cameraAuthorizer: CameraAuthorizer

    private var initializedAccount: InitializedAccount?

    // MARK: - Init -

    init(container: Container) {
        self.container            = container
        self.flipClient           = container.flipClient
        self.sessionAuthenticator = container.sessionAuthenticator
        self.cameraAuthorizer     = CameraAuthorizer()
    }

    // MARK: - Action -

    func loginAction() {
        let hasAccounts = sessionAuthenticator.accountManager
            .fetchHistorical()
            .contains { $0.deletionDate == nil }

        if hasAccounts {
            navigateToAccountSelection()
        } else {
            navigateToLogin()
        }
    }

    func createAccountAction() {
        inflightMnemonic = MnemonicPhrase.generate(.words12)

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
                dialogItem = .init(
                    style: .destructive,
                    title: "Failed to Save",
                    subtitle: "Please allow Flipcash access to Photos in Settings in order to save your Access Key.",
                    dismissable: true
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
                showAccountCreationError(error)
            }
        }

        Analytics.buttonTapped(name: .saveAccessKey)
    }

    func wroteDownAction() {
        dialogItem = .init(
            style: .destructive,
            title: "Are You Sure?",
            subtitle: "These 12 words are the only way to recover your Flipcash account. Make sure you wrote them down, and keep them private and safe.",
            dismissable: true
        ) {
            .destructive("Yes, I Wrote Them Down") { [weak self] in
                Task {
                    do {
                        try await self?.completeAccountCreation()
                    } catch {
                        self?.showAccountCreationError(error)
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

        completeOnboardingAndLogin()

        try await Task.delay(milliseconds: 500) // Delay deferred state change
    }

    private func showAccountCreationError(_ error: Error) {
        dialogItem = .init(
            style: .destructive,
            title: "Something Went Wrong",
            subtitle: "We couldn't create your account. Please try again.",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }

        ErrorReporting.captureError(error)
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

    func allowCameraAccessAction() {
        Task {
            do {
                // Regardless of authorization status
                // continue to finalize the account,
                // they'll have an opportunity to grant
                // access on the camera screen
                _ = try await cameraAuthorizer.authorize()
            } catch {}
            completeOnboardingAndLogin()
        }

        Analytics.buttonTapped(name: .allowCamera)
    }

    func allowPushPermissionsAction() {
        Task {
            navigateToCameraAccessScreen()
        }

        Analytics.buttonTapped(name: .allowPush)
    }

    func skipPushPermissionsAction() {
        navigateToCameraAccessScreen()

        Analytics.buttonTapped(name: .skipPush)
    }

    // MARK: - Registration -

    private func registerAccount(mnemonic: MnemonicPhrase) async throws {
        let owner = mnemonic.solanaKeyPair()

        Analytics.createAccount(owner: owner.publicKey)

        try await flipClient.register(owner: owner)

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

    func navigateToCameraAccessScreen() {
        path.append(.cameraAccess)
    }
}

// MARK: - Path -

enum OnboardingPath {
    case accountSelection
    case login
    case accessKey
    case accessKeyHelp
    case pushPermissions
    case cameraAccess
}
