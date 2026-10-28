//
//  OnboardingResumeTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import UserNotifications
import FlipcashCore
@testable import Flipcash

@Suite("Onboarding resume", .serialized)
@MainActor
struct OnboardingResumeTests {

    private static let userID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
    private static let owner = KeyAccount.mock.ownerPublicKey

    private final class Finished {
        var accounts: [InitializedAccount] = []
    }

    private func makeViewModel(
        push: UNAuthorizationStatus,
        named: Bool,
        finished: Finished
    ) -> OnboardingViewModel {
        OnboardingViewModel(
            container: Container(),
            pushStatus: { push },
            hasDisplayName: { _ in named },
            finishLogin: { finished.accounts.append($0) }
        )
    }

    private func account() -> InitializedAccount {
        InitializedAccount(keyAccount: .mock, userID: Self.userID)
    }

    // MARK: - Launch -

    @Test("An account whose marker is false relaunches into onboarding, not home")
    func markerFalse_resumesOnboarding() {
        OnboardingProgress.setCompleted(false, owner: Self.owner)
        defer { OnboardingProgress.setCompleted(true, owner: Self.owner) }

        #expect(OnboardingProgress.launchRoute(for: Self.owner) == .resumeOnboarding)
    }

    /// Builds that predate the marker never wrote one; sending those users back through
    /// onboarding on upgrade is the regression this guards.
    @Test("An account with no marker goes home, so upgraded users skip onboarding")
    func markerAbsent_goesHome() {
        let stranger = MnemonicPhrase.generate(.words12).solanaKeyPair().publicKey

        #expect(OnboardingProgress.isCompleted(owner: stranger))
        #expect(OnboardingProgress.launchRoute(for: stranger) == .home)
    }

    /// The keychain keeps the signed-in account across an uninstall while UserDefaults does
    /// not, so the reinstall looks like an upgrade (no marker) unless the first launch says otherwise.
    @Test("A first launch that finds a signed-in account is a reinstall and resumes onboarding")
    func freshInstall_withAccount_resumesOnboarding() {
        let owner = MnemonicPhrase.generate(.words12).solanaKeyPair().publicKey
        defer { OnboardingProgress.setCompleted(true, owner: owner) }

        #expect(OnboardingProgress.launchRoute(for: owner, isFreshInstall: true) == .resumeOnboarding)
        #expect(OnboardingProgress.launchRoute(for: owner) == .resumeOnboarding)
    }

    @Test("Resuming with no display name starts at the name step and does not log in")
    func resume_withoutName_startsAtName() async {
        let finished = Finished()
        let viewModel = makeViewModel(push: .notDetermined, named: false, finished: finished)

        await viewModel.resumeOnboarding(with: account())

        #expect(viewModel.path == [.displayName])
        #expect(finished.accounts.isEmpty)
    }

    @Test("Resuming with a name and undecided push starts at the push step and does not log in")
    func resume_withName_startsAtPush() async {
        let finished = Finished()
        let viewModel = makeViewModel(push: .notDetermined, named: true, finished: finished)

        await viewModel.resumeOnboarding(with: account())

        #expect(viewModel.path == [.pushNotifications])
        #expect(finished.accounts.isEmpty)
    }

    /// An unreadable profile is reported as "no name", the same as Android's null-profile check.
    /// Resume and interactive login share this gate, so one case covers both.
    @Test("An unreadable profile holds the user on the name step")
    func resume_unreadableProfile_holdsOnName() async {
        let finished = Finished()
        let viewModel = makeViewModel(push: .authorized, named: false, finished: finished)

        await viewModel.resumeOnboarding(with: account())

        #expect(viewModel.path == [.displayName])
        #expect(finished.accounts.isEmpty)
    }

    // MARK: - Interactive login -

    @Test("An interactive login with push already decided goes straight home and marks onboarding done")
    func interactive_pushAuthorized_goesHome() async {
        OnboardingProgress.setCompleted(false, owner: Self.owner)
        defer { OnboardingProgress.setCompleted(true, owner: Self.owner) }
        let finished = Finished()
        let viewModel = makeViewModel(push: .authorized, named: true, finished: finished)

        await viewModel.resumeOnboarding(with: account())

        #expect(finished.accounts.count == 1)
        #expect(viewModel.path.isEmpty)
        #expect(OnboardingProgress.isCompleted(owner: Self.owner))
    }

    @Test("An interactive login with undecided push shows the push step and stays in onboarding")
    func interactive_pushUndetermined_showsPush() async {
        OnboardingProgress.setCompleted(false, owner: Self.owner)
        defer { OnboardingProgress.setCompleted(true, owner: Self.owner) }
        let finished = Finished()
        let viewModel = makeViewModel(push: .notDetermined, named: true, finished: finished)

        await viewModel.resumeOnboarding(with: account())

        #expect(viewModel.path == [.pushNotifications])
        #expect(finished.accounts.isEmpty)
        #expect(!OnboardingProgress.isCompleted(owner: Self.owner))
    }

    @Test("Beginning onboarding holds the account without opening the session")
    func beginOnboarding_holdsAccount() {
        let authenticator = SessionAuthenticator(container: Container())

        authenticator.beginOnboarding(with: account())

        #expect(authenticator.pendingOnboarding?.keyAccount.ownerPublicKey == Self.owner)
        #expect(!authenticator.isLoggedIn)
    }
}
