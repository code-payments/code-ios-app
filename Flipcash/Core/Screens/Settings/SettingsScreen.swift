//
//  SettingsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The Settings list, pushed from the gear on the You tab: the profile editors,
/// the account-level actions, and the version footer that doubles as the
/// beta-access easter egg.
///
/// The row icons track Android's through the nearest SF Symbol. Profile Picture
/// is the exception: `familiar_face_and_zone` has no SF equivalent, so it ships
/// as an asset.
struct SettingsScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session
    @Environment(BetaFlags.self) private var betaFlags
    @Environment(SessionAuthenticator.self) private var sessionAuthenticator
    @Environment(ContactSyncController.self) private var contactSyncController
    @Environment(ToastController.self) private var toasts

    @State private var dialogItem: DialogItem?
    /// The version footer's beta-access easter egg — the tap count and the line
    /// it shows for the last few taps.
    @State private var versionUnlock = VersionTapUnlock()

    // Horizontal inset lives on the rows, not the list: the section headers
    // carry their own 20pt.
    private let insets = EdgeInsets(top: 25, leading: 20, bottom: 25, trailing: 20)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    securitySection
                    privacySection
                    advancedSection
                    accountSection
                    versionFooter
                        .padding(.top, 32)
                }
                .font(.appDisplayXS)
                .foregroundStyle(.textMain)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
    }

    // MARK: - Sections -

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader("Security")

            SettingsRow(systemImage: "key.horizontal", title: "Access Key", insets: insets) {
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
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader("Privacy")

            SettingsRow(systemImage: "nosign", title: "Blocked", insets: insets) {
                router.push(.blockedUsers)
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader("Advanced")

            SettingsRow(systemImage: "flask", title: "Beta Features", insets: insets) {
                router.push(.settingsAdvancedBetaFeatures)
            }

            SettingsRow(systemImage: "doc.text", title: "Application Logs", insets: insets) {
                router.push(.settingsApplicationLogs)
            }

            if betaFlags.canSwitchAccounts {
                SettingsRow(asset: .switchAccounts, title: "Switch Accounts", badge: .beta, insets: insets) {
                    router.push(.settingsAccountSelection)
                }
                .accessibilityIdentifier("account-switch-accounts-row")
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader("Account")

            if betaFlags.canViewAccountInfo {
                SettingsRow(systemImage: "person.crop.circle", title: "Account Info", badge: .beta, insets: insets) {
                    router.push(.accountInfo)
                }
                .accessibilityIdentifier("settings-account-info-row")
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
    }

    private var versionFooter: some View {
        Button {
            let message = versionUnlock.registerTap(isUnlocked: betaFlags.accessGranted) {
                betaFlags.setAccessGranted(!betaFlags.accessGranted)
            }
            if let message {
                // Two seconds and swapped in place, so consecutive taps read as one countdown. Without an action the toast
                // lets taps through, so it never blocks the version string at the bottom of the list.
                toasts.show(
                    .init(message, messageIdentifier: "you-version-toast", width: .fit, duration: .seconds(2)),
                    inPlace: true
                )
            }
        } label: {
            Text("Version \(AppMeta.version) • Build \(AppMeta.build)")
                .lineLimit(1)
                .font(.appTextHeading)
                .foregroundStyle(Color.textSecondary)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("you-version-footer")
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
