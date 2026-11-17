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

    /// True once ``resumeOnboarding(with:)`` has taken over: the flow was entered from a launch
    /// or an interactive login rather than from "Create a New Account".
    private(set) var isResumedFlow = false

    /// True from ``resumeOnboarding(with:)`` until its first step replaces the path, so that
    /// step becomes the stack's first screen instead of stacking over the intro or login.
    @ObservationIgnored private var awaitingResumedRoot = false
    @ObservationIgnored private var resumedOwner: PublicKey?
    @ObservationIgnored private let pushStatus: () async -> UNAuthorizationStatus
    @ObservationIgnored private let hasDisplayName: (InitializedAccount) async -> Bool
    @ObservationIgnored private let finishLogin: (InitializedAccount) -> Void

    /// Built on first call to ``navigateToDisplayName``; the display-name step
    /// runs pre-login, so it owns its submission against the in-flight owner.
    var nameViewModel: OnboardingNameViewModel?

    // MARK: - Group Money flow -

    /// Whether this new account goes through the Group Money steps (phone, code, email, then
    /// name) instead of the access key. Read from the gate once, at the Create tap.
    private(set) var isGroupMoneyFlow = false

    /// An error shown over the intro, where the Group Money flow registers the account.
    var introDialogItem: DialogItem?

    /// The account creation started by the last Create tap, for tests to await.
    @ObservationIgnored private(set) var accountCreation: Task<Void, Never>?

    /// Shared by the phone entry and code steps; built once the account is registered.
    var phoneViewModel: PhoneVerificationViewModel?

    /// Built when the phone is verified.
    var emailViewModel: OnboardingEmailViewModel?

    /// True while the Create tap registers a Group Money account. Create and Log In do nothing
    /// until it finishes: a second registration would mint a second account.
    private(set) var isCreatingAccount = false

    @ObservationIgnored private let isGroupMoneyGateOpen: () -> Bool

    /// The name step's words for this flow.
    var nameCopy: OnboardingNameCopy {
        isGroupMoneyFlow ? .groupMoney : .standard
    }

    // MARK: - Init -

    /// The closures are seams for tests; the defaults read the real notification status and
    /// profile, and open the session.
    ///
    /// - Parameters:
    ///   - pushStatus: the current notification authorization.
    ///   - hasDisplayName: whether the account's profile already has a display name.
    ///   - finishLogin: opens the session once onboarding is done.
    ///   - isGroupMoneyGateOpen: whether a new account takes the Group Money steps. Defaults to
    ///     ``BetaFlags/opensGroupMoneyOnboarding``.
    init(
        container: Container,
        pushStatus: @escaping () async -> UNAuthorizationStatus = { await PushController.fetchStatus().authorizationStatus },
        hasDisplayName: ((InitializedAccount) async -> Bool)? = nil,
        finishLogin: ((InitializedAccount) -> Void)? = nil,
        isGroupMoneyGateOpen: (() -> Bool)? = nil
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
        self.isGroupMoneyGateOpen = isGroupMoneyGateOpen ?? { [betaFlags = container.betaFlags] in
            betaFlags.opensGroupMoneyOnboarding
        }
    }

    // MARK: - Action -

    func loginAction() {
        guard !isCreatingAccount else { return }

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
        guard !isCreatingAccount else { return }

        inflightMnemonic = MnemonicPhrase.generate(.words12)
        nameViewModel = nil
        phoneViewModel = nil
        emailViewModel = nil
        isGroupMoneyFlow = isGroupMoneyGateOpen()

        if isGroupMoneyFlow {
            // The access key step is skipped, so the account is registered here, behind the
            // Create button's loading state, before the phone step can link a number to it.
            isCreatingAccount = true
            let mnemonic = inflightMnemonic
            accountCreation = Task { [weak self] in
                await self?.registerGroupMoneyAccount(mnemonic: mnemonic)
            }
        } else {
            navigateToAccessKey()
        }

        Analytics.buttonTapped(name: .createAccount)
    }

    private func registerGroupMoneyAccount(mnemonic: MnemonicPhrase) async {
        defer { isCreatingAccount = false }

        do {
            try await registerAccount(mnemonic: mnemonic)
        } catch {
            // The account never became current on this device, so a Log In from the intro gets
            // today's onboarding. A failure after the server registered the owner leaves that
            // account unreachable: the next Create mints a new key.
            isGroupMoneyFlow = false
            introDialogItem = Self.accountCreationError
            return
        }

        navigateToEnterPhoneNumber()
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

    func completeAccountCreation() async throws {
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
    /// later, in-app. A new Group Money account has no push step and goes home;
    /// a resumed account keeps it.
    private func advanceFromNameStep() async {
        if isGroupMoneyFlow {
            completeOnboardingAndLogin()
            return
        }

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
        dialogItem = Self.accountCreationError
    }

    private static var accountCreationError: DialogItem {
        .error(
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
        Analytics.createAccount()

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
        // The task that calls this restarts when the intro swaps for the stack; one run is enough.
        guard resumedOwner != account.keyAccount.ownerPublicKey else { return }
        resumedOwner = account.keyAccount.ownerPublicKey
        initializedAccount = account
        nameViewModel = nil
        isResumedFlow = true
        awaitingResumedRoot = true

        guard !(await hasDisplayName(account)) else {
            await advanceFromNameStep()
            return
        }

        navigateToDisplayName(owner: account.keyAccount.owner)
    }

    /// Longest the resume screen waits on the profile before treating it as unreadable.
    private static let profileLookupTimeout: Double = 5

    private static func lookUpDisplayName(
        for account: InitializedAccount,
        flipClient: FlipClient,
        accountManager: AccountManager
    ) async -> Bool {
        do {
            let profile = try await withTimeout(seconds: profileLookupTimeout) {
                try await flipClient.fetchProfile(userID: account.userID, owner: account.keyAccount.owner)
            }
            accountManager.cacheProfile(profile, ownerPublicKey: account.keyAccount.ownerPublicKey)
            return profile.displayName?.isEmpty == false
        } catch {
            // Unreadable profile: trust a name cached on the account's keychain entry, and
            // otherwise treat the name as missing. Matches Android (a null profile counts as
            // no display name), and every account needs a name for tips and chat.
            let cached = accountManager.fetchHistorical()
                .first { $0.account.ownerPublicKey == account.keyAccount.ownerPublicKey }?
                .displayName
            return cached?.isEmpty == false
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

    /// Whether `step` hides its back button, which also turns off swipe-back.
    ///
    /// A new account hides it on the access key and name steps only; a Group Money account hides
    /// it on phone entry, email and name. A resumed flow also hides
    /// it on its first screen so it can't back out to the intro or login; a later push step may
    /// return to the name step only when the name step is in this flow's path.
    func hidesBackButton(for step: OnboardingPath) -> Bool {
        guard isResumedFlow else {
            if isGroupMoneyFlow {
                // The account is registered before phone entry, so backing out to the intro would
                // invite a second Create. The code step may return to phone entry; the email step
                // follows a verified number and has nothing to return to.
                return step == .enterPhoneNumber || step == .email || step == .displayName
            }
            return step == .accessKey || step == .displayName
        }
        return step == .displayName || path.first == step
    }

    private func place(_ step: OnboardingPath) {
        if awaitingResumedRoot {
            awaitingResumedRoot = false
            path = [step]
        } else {
            path.append(step)
        }
    }

    func navigateToPushNotifications() {
        place(.pushNotifications)
    }

    func navigateToPushNotificationsDenied() {
        path.append(.pushNotificationsDenied)
    }

    /// Phone entry, the first Group Money step. One view model serves phone entry and the code
    /// step, so a back from the code step keeps the number.
    func navigateToEnterPhoneNumber() {
        guard let initializedAccount else { return }

        let vm = PhoneVerificationViewModel(
            owner: initializedAccount.keyAccount.owner,
            flipClient: container.flipClient,
        )
        vm.onCodeRequested = { [weak self] in
            self?.path.append(.confirmPhoneNumberCode)
        }
        vm.onVerified = { [weak self] in
            self?.navigateToEmail()
        }
        phoneViewModel = vm
        path = [.enterPhoneNumber]
    }

    func navigateToEmail() {
        guard let initializedAccount else { return }

        let vm = OnboardingEmailViewModel(
            owner: initializedAccount.keyAccount.owner,
            flipClient: container.flipClient
        )
        vm.onComplete = { [weak self] in
            self?.navigateToDisplayName(owner: initializedAccount.keyAccount.owner)
        }
        emailViewModel = vm
        path.append(.email)
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
        place(.displayName)
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
    case enterPhoneNumber
    case confirmPhoneNumberCode
    case email
}

private struct LookupTimedOut: Error {}

/// Runs `operation`, throwing ``LookupTimedOut`` if it hasn't finished within `seconds`.
///
/// Races two unstructured tasks rather than a task group: a group waits for every child, and a
/// gRPC call that ignores cancellation would hold the caller past the deadline.
private func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    let gate = OnceGate()
    return try await withCheckedThrowingContinuation { continuation in
        Task {
            do {
                let value = try await operation()
                if gate.claim() { continuation.resume(returning: value) }
            } catch {
                if gate.claim() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if gate.claim() { continuation.resume(throwing: LookupTimedOut()) }
        }
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// True for the first caller only.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
