//
//  SettingsAdvancedFeaturesScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The Advanced settings list (Figma node 9279:121978): the account-level
/// actions — Access Key, Log Out, Delete Account — alongside Beta Features and
/// Application Logs. My Account keeps only the rows about *this* account's
/// people (Blocked, Switch Accounts).
struct SettingsAdvancedFeaturesScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(SessionAuthenticator.self) private var sessionAuthenticator
    @Environment(ContactSyncController.self) private var contactSyncController
    @Environment(BetaFlags.self) private var betaFlags

    @State private var dialogItem: DialogItem?

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(asset: .key, title: "Access Key", insets: insets) {
                        dialogItem = .alert(
                            title: "View Your Access Key?",
                            subtitle: "Your Access Key will grant access to your Flipcash account. Keep it private and safe"
                        ) {
                            DialogAction.destructive("View Access Key") {
                                router.push(.accessKey)
                            }
                            DialogAction.cancel()
                        }
                    }

                    // Hidden outright when there is nothing behind it: the
                    // developer flags only exist once access is unlocked, so
                    // without any public flag the row would open an empty screen.
                    if betaFlags.hasVisibleOptions {
                        SettingsRow(asset: .debug, title: "Beta Features", insets: insets) {
                            router.push(.settingsAdvancedBetaFeatures)
                        }
                    }

                    SettingsRow(systemImage: "doc.text", title: "Application Logs", insets: insets) {
                        router.push(.settingsApplicationLogs)
                    }

                    SettingsRow(asset: .logout, title: "Log Out", insets: insets) {
                        dialogItem = .alert(
                            title: "Are You Sure You Want To Log Out?",
                            subtitle: "You can get into this account using your Access Key"
                        ) {
                            DialogAction.destructive("Log Out") {
                                logout()
                            }
                            DialogAction.cancel()
                        }
                    }

                    SettingsRow(asset: .delete, title: "Delete Account", insets: insets) {
                        dialogItem = .alert(
                            title: "Permanently Delete Account?",
                            subtitle: "This will permanently delete your Flipcash account"
                        ) {
                            DialogAction.destructive("Permanently Delete Account") {
                                deleteAccount()
                            }
                            DialogAction.cancel()
                        }
                    }
                }
                .font(.appDisplayXS)
                .foregroundStyle(.textMain)
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("Advanced")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
    }

    // MARK: - Actions -

    private func deleteAccount() {
        Task {
            router.dismissSheet()
            try await Task.delay(milliseconds: 250)
            // No server-side account deletion exists; logout only tears down
            // locally. Wipe the server's stored contact set first so it isn't
            // retained after the account is "deleted". Best-effort — must run
            // before logout while the session can still authenticate the call.
            await contactSyncController.clearServerContactSetForAccountDeletion()
            sessionAuthenticator.logout()
        }
    }

    private func logout() {
        Task {
            router.dismissSheet()
            try await Task.delay(milliseconds: 250)
            sessionAuthenticator.logout()
        }
    }
}
