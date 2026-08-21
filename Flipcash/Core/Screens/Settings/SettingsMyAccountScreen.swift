//
//  SettingsMyAccountScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The My Account settings list (Figma node 9277:121893): who this account
/// deals with. The account-level actions — Access Key, Log Out, Delete
/// Account — live on Advanced.
struct SettingsMyAccountScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(BetaFlags.self) private var betaFlags

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                list()
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("My Account")
        .toolbarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func list() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(systemImage: "nosign", title: "Blocked", insets: insets) {
                router.push(.blockedUsers)
            }

            if betaFlags.accessGranted {
                SettingsRow(asset: .switchAccounts, title: "Switch Accounts", badge: .beta, insets: insets) {
                    router.push(.settingsAccountSelection)
                }
            }
        }
        .font(.appDisplayXS)
        .foregroundStyle(.textMain)
    }
}
