//
//  SettingsMyAccountScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The My Account settings list (Figma node 9544:18478): who this account
/// deals with, and the profile it presents. The account-level actions — Access
/// Key, Switch Accounts, Log Out, Delete Account — live on Advanced.
///
/// The design also lists Require Biometrics, which isn't here: iOS has no
/// biometrics setting to toggle.
///
/// The row icons track Android's (`MyAccountMenuItems.kt`) through the nearest
/// SF Symbol, so the two platforms read alike without importing Material into
/// a system-symbol set. Profile Picture is the exception: `familiar_face_and_zone`
/// has no SF equivalent, so it ships as an asset.
struct SettingsMyAccountScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                list()
            }
            .softScrollEdge(for: .top)
            .padding(.horizontal, 20)
        }
        .navigationTitle("My Account")
        .toolbarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func list() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(systemImage: "person.text.rectangle", title: "Display Name", insets: insets) {
                router.push(.changeDisplayName)
            }

            // No balance gate here: the gate exists to stop squatting at claim time. A user who
            // already holds a handle has cleared it, and re-gating a change would hold their
            // handle hostage to a balance that has since moved.
            if let username = session.profile?.username {
                SettingsRow(systemImage: "at", title: "Username", insets: insets) {
                    router.push(.username(username))
                }
                .accessibilityIdentifier("account-change-username-row")
            }

            SettingsRow(asset: .profilePicture, title: "Profile Picture", insets: insets) {
                router.push(.changeProfilePicture)
            }
            .accessibilityIdentifier("account-profile-picture-row")

            SettingsRow(asset: .coins, title: "Minimum Tip", insets: insets) {
                router.push(.setMinimumTip(isSetupStep: false))
            }
            .accessibilityIdentifier("account-minimum-tip-row")

            SettingsRow(systemImage: "nosign", title: "Blocked", insets: insets) {
                router.push(.blockedUsers)
            }
        }
        .font(.appDisplayXS)
        .foregroundStyle(.textMain)
    }
}
