//
//  SettingsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The Settings list, pushed from the gear on the You tab: the profile editors,
/// the account-level actions, and the version card that doubles as the
/// beta-access easter egg while it sits inline.
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
    @Environment(UpdateAvailability.self) private var updateAvailability

    @State private var dialogItem: DialogItem?
    /// The version card's beta-access easter egg — the tap count and the line
    /// it shows for the last few taps.
    @State private var versionUnlock = VersionTapUnlock()
    /// How the list fits the screen, which is when the inline state's bottom fade belongs.
    @State private var scrollFit = ProfileScrollFit()

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
                    if !cardState.isPinned {
                        versionCard
                            .padding(.top, 8)
                    }
                }
                .font(.appDisplayXS)
                .foregroundStyle(.textMain)
                .padding(.bottom, 24)
            }
            .profileScrollFit($scrollFit)
        }
        // Pinned, the card sits on glass in the bar and the soft scroll edge fades rows under it; its
        // inset keeps Log Out and Delete Account clear of the card. Inline the bar is empty, which
        // draws no edge, so it carries the barless fade the profiles use while rows run past the screen.
        .scrollEdgeBar(.bottom) {
            if cardState.isPinned {
                versionCard
                    .padding(.bottom, 16)
            } else {
                Color.clear
                    .frame(height: 0)
                    .profileBarlessFade(isActive: scrollFit.fadesBottom)
            }
        }
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
        // The update toast would sit on the pinned card, so it comes down while Settings is open.
        .onAppear { updateAvailability.dismissToast(on: toasts) }
    }

    // MARK: - Sections -

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader("Security")

            SettingsRow(icon: .key1, title: "Access Key", insets: insets) {
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
            .lastInSection()
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader("Privacy")

            SettingsRow(icon: .circleBanSign, title: "Blocked", insets: insets) {
                router.push(.blockedUsers)
            }

            SettingsRow(icon: .globe, title: "Trusted Websites", insets: insets) {
                router.push(.trustedWebsites)
            }
            .lastInSection()
            .accessibilityIdentifier("settings-trusted-websites-row")
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader("Advanced")

            SettingsRow(icon: .bug, title: "Beta Features", insets: insets) {
                router.push(.settingsAdvancedBetaFeatures)
            }

            let logs = SettingsRow(icon: .fileText, title: "Application Logs", insets: insets) {
                router.push(.settingsApplicationLogs)
            }
            if betaFlags.canSwitchAccounts { logs } else { logs.lastInSection() }

            if betaFlags.canSwitchAccounts {
                SettingsRow(icon: .group1, title: "Switch Accounts", badge: .beta, insets: insets) {
                    router.push(.settingsAccountSelection)
                }
                .lastInSection()
                .accessibilityIdentifier("account-switch-accounts-row")
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader("Account")

            if betaFlags.canViewAccountInfo {
                SettingsRow(icon: .circlePerson, title: "Account Info", badge: .beta, insets: insets) {
                    router.push(.accountInfo)
                }
                .accessibilityIdentifier("settings-account-info-row")
            }

            SettingsRow(icon: .arrowBoxLeft, title: "Log Out", insets: insets) {
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
            .actsInPlace()
            SettingsRow(icon: .trashCan, title: "Delete Account", insets: insets) {
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
            .actsInPlace()
            .destructive()
            .lastInSection()
        }
    }

    private var cardState: SettingsVersionCardState {
        SettingsVersionCardState(
            newerVersion: updateAvailability.newerVersion,
            isDebugBuild: SettingsVersionCardState.isDebugBuild,
            channel: updateAvailability.channel,
            installedBuild: updateAvailability.installedBuild,
            latestTestFlightBuild: updateAvailability.latestTestFlightBuild,
            isStaff: session.isStaff
        )
    }

    private var versionCard: some View {
        SettingsVersionCard(state: cardState, onTapVersion: registerVersionTap) {
            switch cardState {
            case .testFlightUpdate, .testFlightNewer: updateAvailability.openTestFlight()
            case .updateAvailable, .upToDate, .debug: updateAvailability.openStore()
            }
        }
    }

    private func registerVersionTap() {
        let message = versionUnlock.registerTap(isUnlocked: betaFlags.accessGranted) {
            betaFlags.setAccessGranted(!betaFlags.accessGranted)
        }
        if let message {
            // Two seconds and swapped in place, so consecutive taps read as one countdown. Without an action the toast
            // lets taps through, so it never blocks the version card.
            toasts.show(
                .init(message, messageIdentifier: "you-version-toast", width: .fit, duration: .seconds(2)),
                inPlace: true
            )
        }
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
