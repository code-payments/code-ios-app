//
//  OnboardingProgress.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Per-account record of whether onboarding finished, so a launch after a kill mid-flow can
/// pick up where the user left off.
///
/// An account with no entry counts as completed: builds that predate the marker never wrote
/// one, and those users must not be sent back through onboarding.
enum OnboardingProgress {

    enum LaunchRoute: Equatable {
        case home
        case resumeOnboarding
    }

    @Defaults(.onboardingCompleted)
    private static var markers: [String: Bool]?

    @Defaults(.onboardingGroupMoney)
    private static var groupMoneyOwners: [String: Bool]?

    /// False only when the account was registered or signed in and never finished onboarding.
    static func isCompleted(owner: PublicKey) -> Bool {
        markers?[owner.base58] ?? true
    }

    static func setCompleted(_ completed: Bool, owner: PublicKey) {
        var updated = markers ?? [:]
        updated[owner.base58] = completed
        markers = updated
    }

    /// Whether the account's onboarding started in the Group Money steps.
    ///
    /// Written when a Create tap finds the gate open and cleared when onboarding finishes, so a
    /// launch after a kill resumes in the flow the account started in, even if the gate has
    /// changed since. No entry means today's steps: accounts created with the gate closed, logins,
    /// and accounts left mid-onboarding by builds that predate the record.
    static func startedInGroupMoney(owner: PublicKey) -> Bool {
        groupMoneyOwners?[owner.base58] ?? false
    }

    static func setStartedInGroupMoney(_ started: Bool, owner: PublicKey) {
        var updated = groupMoneyOwners ?? [:]
        updated[owner.base58] = started ? true : nil
        groupMoneyOwners = updated.isEmpty ? nil : updated
    }

    /// Where a launch with `owner` as the current account should land.
    ///
    /// The keychain outlives an uninstall but UserDefaults does not, so a first launch that
    /// already finds a signed-in account is a reinstall: the permission decisions are gone and
    /// the marker with them. That case reopens the marker so the push step is offered again.
    static func launchRoute(for owner: PublicKey, isFreshInstall: Bool = false) -> LaunchRoute {
        if isFreshInstall {
            setCompleted(false, owner: owner)
        }
        return isCompleted(owner: owner) ? .home : .resumeOnboarding
    }
}
