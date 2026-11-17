//
//  GroupMoneyOnboardingSpecTests.swift
//  FlipcashTests
//
//  New-account onboarding when the Group Money gate is open: Create registers the account, then
//  phone number, code, email (linked without a code), name, home. Neither the access key screen
//  nor the notification permission step is shown. Frames 2-03 to 2-06. Numbered by the decision table's rules;
//  written before the implementation, so each test pins an outcome rather than a mechanism.
//

import Foundation
import Testing
import UserNotifications
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Group Money onboarding spec", .serialized)
struct GroupMoneyOnboardingSpecTests {

    nonisolated fileprivate static let userID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!

    // MARK: - Harness -

    /// Answers the registration's server calls without a server, and records them.
    @MainActor
    private final class Remote {
        var registered: [PublicKey] = []
        var loggedIn: [PublicKey] = []
        var created: [PublicKey] = []
        var registerError: Error?
        var registerDelay: Duration = .zero

        func install(on authenticator: SessionAuthenticator) {
            authenticator.remote = AccountRemote(
                register: { [self] owner in
                    if registerDelay > .zero { try await Task.sleep(for: registerDelay) }
                    if let registerError { throw registerError }
                    registered.append(owner.publicKey)
                    return GroupMoneyOnboardingSpecTests.userID
                },
                login: { [self] owner in
                    loggedIn.append(owner.publicKey)
                    return GroupMoneyOnboardingSpecTests.userID
                },
                createPrimaryAccounts: { [self] cluster in
                    created.append(cluster.authority.keyPair.publicKey)
                }
            )
        }
    }

    @MainActor
    private final class Counter {
        var reads = 0
        var isOpen: Bool

        init(isOpen: Bool) { self.isOpen = isOpen }

        func read() -> Bool {
            reads += 1
            return isOpen
        }
    }

    @MainActor
    private final class Finished {
        var accounts: [InitializedAccount] = []
    }

    @MainActor
    private struct Harness {
        let container: Container
        let remote: Remote
        let finished: Finished
        let viewModel: OnboardingViewModel

        /// The owner the Create tap registered, if any.
        var registeredOwner: PublicKey? { remote.registered.first }

        /// Leaves no account or onboarding marker behind for the next test.
        func cleanUp() {
            for owner in remote.registered {
                OnboardingProgress.setCompleted(true, owner: owner)
            }
            container.accountManager.nukeForUITesting()
        }
    }

    private struct RegistrationFailed: Error {}

    private func makeHarness(
        gate: Counter,
        push: UNAuthorizationStatus = .notDetermined
    ) -> Harness {
        let container = Container()
        let remote = Remote()
        remote.install(on: container.sessionAuthenticator)
        let finished = Finished()
        let viewModel = OnboardingViewModel(
            container: container,
            pushStatus: { push },
            hasDisplayName: { _ in false },
            finishLogin: { finished.accounts.append($0) },
            isGroupMoneyGateOpen: gate.read
        )
        return Harness(container: container, remote: remote, finished: finished, viewModel: viewModel)
    }

    /// Taps Create and waits for whatever the tap started.
    private func tapCreate(_ harness: Harness) async {
        harness.viewModel.createAccountAction()
        await harness.viewModel.accountCreation?.value
    }

    /// Drives the gated flow from a registered account to the name step, the way the screens do.
    private func passPhoneAndEmail(_ harness: Harness) async throws {
        let phone = try #require(harness.viewModel.phoneViewModel)
        phone.onCodeRequested?()
        phone.onVerified?()
        let email = try #require(harness.viewModel.emailViewModel)
        email.onComplete?()
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - 1. Flow -

    @Test("1.1 gate open: Create registers the account and goes straight to the phone number")
    func gateOpen_createRegistersAndShowsPhone() async {
        let harness = makeHarness(gate: Counter(isOpen: true))
        defer { harness.cleanUp() }

        await tapCreate(harness)

        #expect(harness.remote.registered.count == 1)
        #expect(harness.viewModel.path == [.enterPhoneNumber])
        #expect(harness.viewModel.isGroupMoneyFlow)
    }

    @Test("1.2 gate open: phone, code, email, name, then home; never the access key or notification permission")
    func gateOpen_stepOrder() async throws {
        let harness = makeHarness(gate: Counter(isOpen: true), push: .notDetermined)
        defer { harness.cleanUp() }
        await tapCreate(harness)

        let phone = try #require(harness.viewModel.phoneViewModel)
        phone.onCodeRequested?()
        #expect(harness.viewModel.path == [.enterPhoneNumber, .confirmPhoneNumberCode])

        phone.onVerified?()
        #expect(harness.viewModel.path == [.enterPhoneNumber, .confirmPhoneNumberCode, .email])

        let email = try #require(harness.viewModel.emailViewModel)
        email.onComplete?()
        #expect(harness.viewModel.path == [.enterPhoneNumber, .confirmPhoneNumberCode, .email, .displayName])

        let name = try #require(harness.viewModel.nameViewModel)
        name.onComplete?()
        await waitUntil { !harness.finished.accounts.isEmpty || harness.viewModel.path.last == .pushNotifications }

        let owner = try #require(harness.registeredOwner)
        #expect(harness.finished.accounts.map(\.keyAccount.ownerPublicKey) == [owner])
        #expect(OnboardingProgress.isCompleted(owner: owner))
        #expect(harness.viewModel.path == [.enterPhoneNumber, .confirmPhoneNumberCode, .email, .displayName])
        #expect(!harness.viewModel.path.contains(.accessKey))
    }

    @Test("1.3 gate open, notifications already decided: the name step finishes onboarding and logs in")
    func gateOpen_pushDecided_logsIn() async throws {
        let harness = makeHarness(gate: Counter(isOpen: true), push: .authorized)
        defer { harness.cleanUp() }
        await tapCreate(harness)
        try await passPhoneAndEmail(harness)

        try #require(harness.viewModel.nameViewModel).onComplete?()
        await waitUntil { !harness.finished.accounts.isEmpty }

        let owner = try #require(harness.registeredOwner)
        #expect(harness.finished.accounts.map(\.keyAccount.ownerPublicKey) == [owner])
        #expect(OnboardingProgress.isCompleted(owner: owner))
    }

    @Test("1.4 gate closed: Create shows the access key and registers nothing, as today")
    func gateClosed_createShowsAccessKey() async {
        let harness = makeHarness(gate: Counter(isOpen: false))
        defer { harness.cleanUp() }

        await tapCreate(harness)

        #expect(harness.viewModel.path == [.accessKey])
        #expect(harness.remote.registered.isEmpty)
        #expect(harness.viewModel.phoneViewModel == nil)
        #expect(!harness.viewModel.isGroupMoneyFlow)
    }

    @Test("1.7 gate open: an account resumed after a relaunch keeps today's name words and notification step")
    func gateOpen_resumedAccountKeepsPushStep() async throws {
        let harness = makeHarness(gate: Counter(isOpen: true), push: .notDetermined)
        defer { harness.cleanUp() }

        await harness.viewModel.resumeOnboarding(with: Self.resumedAccount)
        #expect(harness.viewModel.path == [.displayName])
        #expect(harness.viewModel.nameCopy == .standard)
        #expect(!harness.viewModel.keepsNavigationBarRow(for: .displayName))

        try #require(harness.viewModel.nameViewModel).onComplete?()
        await waitUntil { harness.viewModel.path.last == .pushNotifications }

        #expect(harness.viewModel.path == [.displayName, .pushNotifications])
        #expect(harness.finished.accounts.isEmpty)
    }

    @Test("1.8 gate open: after a failed Create, a Log In keeps today's name words and notification step")
    func gateOpen_failedCreateThenLogIn_keepsPushStep() async throws {
        let harness = makeHarness(gate: Counter(isOpen: true), push: .notDetermined)
        defer { harness.cleanUp() }
        harness.remote.registerError = RegistrationFailed()
        await tapCreate(harness)

        await harness.viewModel.resumeOnboarding(with: Self.resumedAccount)
        #expect(harness.viewModel.nameCopy == .standard)

        try #require(harness.viewModel.nameViewModel).onComplete?()
        await waitUntil { harness.viewModel.path.last == .pushNotifications || !harness.finished.accounts.isEmpty }

        #expect(harness.viewModel.path == [.displayName, .pushNotifications])
        #expect(harness.finished.accounts.isEmpty)
    }

    /// An account already signed in when onboarding resumes: a relaunch or an interactive login.
    private static var resumedAccount: InitializedAccount {
        InitializedAccount(keyAccount: .mock, userID: userID)
    }

    @Test("1.5 gate open: a failed registration stays on the intro with an error")
    func gateOpen_registrationFails_staysOnIntro() async {
        let harness = makeHarness(gate: Counter(isOpen: true))
        defer { harness.cleanUp() }
        harness.remote.registerError = RegistrationFailed()

        await tapCreate(harness)

        #expect(harness.viewModel.path.isEmpty)
        #expect(harness.viewModel.introDialogItem?.title == "Something Went Wrong")
        #expect(harness.viewModel.phoneViewModel == nil)
        #expect(harness.container.accountManager.fetchCurrentUserAccount() == nil)
    }

    @Test("1.6 gate open: while the account registers, Create and Log In do nothing")
    func gateOpen_tapsDuringRegistrationIgnored() async {
        let harness = makeHarness(gate: Counter(isOpen: true))
        defer { harness.cleanUp() }
        harness.remote.registerDelay = .milliseconds(200)

        harness.viewModel.createAccountAction()
        let first = harness.viewModel.accountCreation
        harness.viewModel.createAccountAction()
        harness.viewModel.loginAction()

        #expect(harness.viewModel.path.isEmpty)
        await first?.value
        await harness.viewModel.accountCreation?.value

        #expect(harness.remote.registered.count == 1)
        #expect(harness.viewModel.path == [.enterPhoneNumber])
    }

    // MARK: - 2. Gate -

    @Test("2.1 the gate is read once, at the Create tap, and carried through the flow")
    func gate_readOnceAtTap() async throws {
        let gate = Counter(isOpen: true)
        let harness = makeHarness(gate: gate)
        defer { harness.cleanUp() }

        await tapCreate(harness)
        gate.isOpen = false
        try await passPhoneAndEmail(harness)

        #expect(gate.reads == 1)
        #expect(harness.viewModel.isGroupMoneyFlow)
        #expect(harness.viewModel.path.last == .displayName)
        #expect(harness.viewModel.nameCopy == .groupMoney)
    }

    @Test("2.2 before sign-in the gate is the Group Money option and the developer unlock, not staff standing")
    func gate_predicate() throws {
        try BetaFlags.withEveryOptionStored {
            let flags = BetaFlags()
            #expect(flags.opensGroupMoneyOnboarding == BetaFlags.showsGroupMoneyUI(
                isEnabled: flags.hasEnabled(.groupMoneyUI),
                isStaff: false,
                accessGranted: flags.accessGranted
            ))

            flags.applyLaunchArgumentOverrides(arguments: ["--beta-flags=groupMoneyUI", "--beta-access-granted"])
            #expect(flags.opensGroupMoneyOnboarding)

            flags.applyLaunchArgumentOverrides(arguments: ["--beta-flags=vibrateOnScan", "--beta-access-granted"])
            #expect(!flags.opensGroupMoneyOnboarding)
        }
    }

    @Test("2.3 a UI test can open the gate at launch without unlocking the device for good")
    func gate_uiTestSeam() throws {
        try BetaFlags.withEveryOptionStored {
            let storedUnlock = BetaFlags().accessGranted
            let launch = BetaFlags()

            launch.applyLaunchArgumentOverrides(arguments: ["--beta-flags=groupMoneyUI", "--beta-access-granted"])

            #expect(launch.accessGranted)
            #expect(launch.showsGroupMoneyUI(isStaff: false))
            #expect(BetaFlags().accessGranted == storedUnlock, "the unlock is not written to the keychain")
        }
    }

    // MARK: - 3. Access key -

    @Test("3.1 gate open: after Create the account is registered, current, and stored as after today's access key step")
    func gateOpen_accountStoredLikeAccessKeyStep() async throws {
        let gated = makeHarness(gate: Counter(isOpen: true))
        await tapCreate(gated)
        let gatedOwner = try #require(gated.registeredOwner)
        let gatedState = StoredAccountState(container: gated.container, owner: gatedOwner)
        gated.cleanUp()

        let closed = makeHarness(gate: Counter(isOpen: false))
        defer { closed.cleanUp() }
        await tapCreate(closed)
        try await closed.viewModel.completeAccountCreation()
        let closedOwner = try #require(closed.registeredOwner)
        let closedState = StoredAccountState(container: closed.container, owner: closedOwner)

        #expect(gatedState == closedState)
        #expect(gatedState == StoredAccountState(
            isCurrent: true,
            userID: Self.userID,
            storedOwners: 1,
            isStored: true,
            onboardingCompleted: false,
            accountsCreated: true
        ))
        #expect(gated.remote.created == [gatedOwner])
    }

    /// What the device holds for a just-registered account, independent of which owner it is.
    private struct StoredAccountState: Equatable {
        var isCurrent: Bool
        var userID: UserID?
        var storedOwners: Int
        var isStored: Bool
        var onboardingCompleted: Bool
        var accountsCreated: Bool

        init(isCurrent: Bool, userID: UserID?, storedOwners: Int, isStored: Bool, onboardingCompleted: Bool, accountsCreated: Bool) {
            self.isCurrent = isCurrent
            self.userID = userID
            self.storedOwners = storedOwners
            self.isStored = isStored
            self.onboardingCompleted = onboardingCompleted
            self.accountsCreated = accountsCreated
        }

        @MainActor
        init(container: Container, owner: PublicKey) {
            let current = container.accountManager.fetchCurrentUserAccount()
            let stored = container.accountManager.fetchActiveHistorical()
            self.isCurrent = current?.keyAccount.ownerPublicKey == owner
            self.userID = current?.userID
            self.storedOwners = stored.count
            self.isStored = stored.contains { $0.account.ownerPublicKey == owner }
            self.onboardingCompleted = OnboardingProgress.isCompleted(owner: owner)
            self.accountsCreated = true
        }
    }

    // MARK: - 4. Phone and code -

    @Test("4.1 the phone steps verify the registered account's number")
    func phone_ownerIsRegisteredAccount() async throws {
        let harness = makeHarness(gate: Counter(isOpen: true))
        defer { harness.cleanUp() }
        await tapCreate(harness)

        let phone = try #require(harness.viewModel.phoneViewModel)
        #expect(phone.owner.publicKey == harness.registeredOwner)
    }

    @Test("4.2 no back from phone entry; back from the code step returns to phone entry")
    func phone_backButtons() async {
        let harness = makeHarness(gate: Counter(isOpen: true))
        defer { harness.cleanUp() }
        await tapCreate(harness)

        #expect(harness.viewModel.hidesBackButton(for: .enterPhoneNumber))
        #expect(!harness.viewModel.hidesBackButton(for: .confirmPhoneNumberCode))
    }

    @Test("4.3 the on-ramp's phone screens keep today's words")
    func phoneCopy_standardUnchanged() {
        let copy = PhoneVerificationCopy.standard
        #expect(copy.entryHeader == nil)
        #expect(copy.entryFieldLabel == nil)
        #expect(copy.entryHint == "Please enter your phone number to continue")
        #expect(copy.codeHeader(phone: "+1 (202) 555-0148", digits: 6) == nil)
        #expect(copy.codeExplanation == "An SMS message was sent to your phone number with a verification code. Please enter the verification code above.")
        #expect(copy.resendTitle == "Didn't get an SMS? Resend")
        #expect(copy.codeButtonTitle == "Confirm")
    }

    @Test("4.4 the onboarding phone screens use the frames' words")
    func phoneCopy_onboarding() {
        let copy = PhoneVerificationCopy.onboarding
        #expect(copy.entryHeader == StepHeaderText(title: "Your phone number", subtitle: "Enter your phone number to create your account."))
        #expect(copy.entryFieldLabel == "Phone number")
        #expect(copy.entryHint == "We'll text you a verification code.")
        #expect(copy.codeHeader(phone: "+1 (202) 555-0148", digits: 6) == StepHeaderText(
            title: "Enter verification code",
            subtitle: "Enter the 6-digit code we sent to +1 (202) 555-0148."
        ))
        #expect(copy.codeExplanation == "This confirms that this number belongs to you.")
        #expect(copy.resendTitle == "Resend code")
    }

    @Test("4.6 the onboarding code screen keeps its button, titled Next as on the other steps")
    func phoneCopy_onboardingCodeButton() {
        // Frame 2-04 draws no button. It stays because it carries the loading state while the
        // code is checked, and Android keeps it too, titled Next.
        #expect(PhoneVerificationCopy.onboarding.codeButtonTitle == "Next")
    }

    @Test("4.7 gate open: phone, code, email and name keep the navigation bar's row, so their titles sit at one height")
    func gateOpen_stepsKeepNavigationBarRow() async {
        let harness = makeHarness(gate: Counter(isOpen: true))
        defer { harness.cleanUp() }
        await tapCreate(harness)

        // Only the code step has a back button; without the row the other three titles sit higher.
        for step: OnboardingPath in [.enterPhoneNumber, .confirmPhoneNumberCode, .email, .displayName] {
            #expect(harness.viewModel.keepsNavigationBarRow(for: step), "\(step)")
        }
    }

    // MARK: - 5. Email -

    @Test("5.1 the email step links the registered account's address")
    func email_ownerIsRegisteredAccount() async throws {
        let harness = makeHarness(gate: Counter(isOpen: true))
        defer { harness.cleanUp() }
        await tapCreate(harness)
        let phone = try #require(harness.viewModel.phoneViewModel)
        phone.onCodeRequested?()
        phone.onVerified?()

        let email = try #require(harness.viewModel.emailViewModel)
        #expect(email.owner.publicKey == harness.registeredOwner)
    }

    @Test("5.2 an address that is not an email cannot be submitted and calls nothing")
    func email_invalidNotSubmitted() async {
        let links = LinkRecorder()
        let viewModel = OnboardingEmailViewModel(owner: KeyAccount.mock.owner, link: links.link)
        viewModel.enteredEmail = "not an email"

        viewModel.submit()
        await viewModel.submission?.value

        #expect(!viewModel.canSubmit)
        #expect(links.emails.isEmpty)
    }

    @Test("5.3 a valid address is linked without a code, then the flow moves on")
    func email_linksAndCompletes() async {
        let links = LinkRecorder()
        let owner = KeyAccount.mock.owner
        let viewModel = OnboardingEmailViewModel(owner: owner, link: links.link)
        var completed = 0
        viewModel.onComplete = { completed += 1 }
        let unverifiedBefore = CoinbaseOrderEmail.unverifiedEmail
        viewModel.enteredEmail = "  joe@example.com "

        #expect(viewModel.canSubmit)
        viewModel.submit()
        await viewModel.submission?.value

        #expect(links.emails == ["joe@example.com"])
        #expect(links.owners == [owner.publicKey])
        #expect(completed == 1)
        #expect(CoinbaseOrderEmail.unverifiedEmail == unverifiedBefore, "the on-ramp's local address is not touched")
    }

    @Test("5.4 a rejected address reads as an invalid email and stays on the step", arguments: [
        (ErrorLinkUnverifiedEmail.rejected, "Invalid Email"),
        (ErrorLinkUnverifiedEmail.denied, "Something Went Wrong"),
        (ErrorLinkUnverifiedEmail.transportFailure, "Something Went Wrong"),
        (ErrorLinkUnverifiedEmail.unknown, "Something Went Wrong"),
    ])
    func email_failureStays(error: ErrorLinkUnverifiedEmail, title: String) async {
        let links = LinkRecorder()
        links.error = error
        let viewModel = OnboardingEmailViewModel(owner: KeyAccount.mock.owner, link: links.link)
        var completed = 0
        viewModel.onComplete = { completed += 1 }
        viewModel.enteredEmail = "joe@example.com"

        viewModel.submit()
        await viewModel.submission?.value

        #expect(links.emails == ["joe@example.com"])
        #expect(viewModel.dialogItem?.title == title)
        #expect(completed == 0)
        #expect(viewModel.buttonState == .normal)
    }

    @MainActor
    private final class LinkRecorder {
        var emails: [String] = []
        var owners: [PublicKey] = []
        var error: Error?

        func link(_ email: String, _ owner: KeyPair) async throws {
            emails.append(email)
            owners.append(owner.publicKey)
            if let error { throw error }
        }
    }

    // MARK: - 7. Name -

    @Test("7.1 gate open: the name step is last, with the frame's words")
    func name_groupMoneyCopy() async throws {
        let harness = makeHarness(gate: Counter(isOpen: true))
        defer { harness.cleanUp() }
        await tapCreate(harness)
        try await passPhoneAndEmail(harness)

        #expect(harness.viewModel.path.last == .displayName)
        #expect(harness.viewModel.nameViewModel != nil)
        #expect(harness.viewModel.nameCopy == .groupMoney)
        #expect(OnboardingNameCopy.groupMoney.title == "Your name")
        #expect(OnboardingNameCopy.groupMoney.hint == "This is how you'll appear in your groups.")
    }

    @Test("7.2 gate closed: the name step keeps today's words")
    func name_standardCopy() async {
        let harness = makeHarness(gate: Counter(isOpen: false))
        defer { harness.cleanUp() }
        await tapCreate(harness)

        #expect(harness.viewModel.nameCopy == .standard)
        #expect(OnboardingNameCopy.standard.title == "What's your name?")
        #expect(OnboardingNameCopy.standard.hint == "This is how you'll appear to others")
    }

    @Test("7.3 gate closed: the access key and name steps keep today's navigation bar")
    func gateClosed_stepsKeepTodaysNavigationBar() async {
        let harness = makeHarness(gate: Counter(isOpen: false))
        defer { harness.cleanUp() }
        await tapCreate(harness)

        #expect(!harness.viewModel.keepsNavigationBarRow(for: .accessKey))
        #expect(!harness.viewModel.keepsNavigationBarRow(for: .displayName))
    }

    // MARK: - 8. Log In -

    @Test("8.1 gate open: Log In goes to login as today and registers nothing")
    func login_unchanged() {
        let harness = makeHarness(gate: Counter(isOpen: true))
        defer { harness.cleanUp() }

        harness.viewModel.loginAction()

        #expect(harness.viewModel.path == [.login])
        #expect(harness.remote.registered.isEmpty)
    }

    // MARK: - 9. Resume (accepted gap) -

    /// Accepted for this beta: resume knows only name and push, so a new account that quits
    /// during phone or email relaunches into the name step and skips them.
    @Test("9.1 gate open: quitting before the name step relaunches into the name step, skipping phone and email")
    func resume_skipsPhoneAndEmail() async throws {
        let harness = makeHarness(gate: Counter(isOpen: true))
        defer { harness.cleanUp() }
        await tapCreate(harness)
        let owner = try #require(harness.registeredOwner)
        #expect(OnboardingProgress.launchRoute(for: owner) == .resumeOnboarding)

        let relaunch = OnboardingViewModel(
            container: harness.container,
            pushStatus: { .notDetermined },
            hasDisplayName: { _ in false },
            finishLogin: { _ in },
            isGroupMoneyGateOpen: { true }
        )
        let account = InitializedAccount(
            keyAccount: try #require(harness.container.accountManager.fetchCurrentUserAccount()).keyAccount,
            userID: Self.userID
        )
        await relaunch.resumeOnboarding(with: account)

        #expect(relaunch.path == [.displayName])
    }
}
