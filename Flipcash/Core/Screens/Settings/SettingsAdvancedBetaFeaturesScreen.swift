//
//  SettingsAdvancedBetaFeaturesScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-06-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.betaflags")

/// The single Beta Features screen, reached from Advanced.
///
/// Everyone sees the public-beta flags; unlocking developer access (ten taps on
/// the version footer) adds the developer flags and the account-unlink actions
/// that used to live on a separate Beta Flags screen.
struct SettingsAdvancedBetaFeaturesScreen: View {

    @Environment(BetaFlags.self) private var betaFlags
    @Environment(Session.self) private var session
    @Environment(Container.self) private var container

    @State private var isConfirmingUnlinkEmail: Bool = false
    @State private var isConfirmingUnlinkPhone: Bool = false
    @State private var unlinkAlertTitle: String?
    @State private var unlinkAlertMessage: String?
    @State private var isShowingUnlinkAlert: Bool = false
    #if DEBUG // LOCAL-TUNER
    /// The tray the showcase has up over this screen. // LOCAL-TUNER
    @State private var showcaseTray: TrayKind? // LOCAL-TUNER
    #endif // LOCAL-TUNER

    private let publicOptions = BetaFlags.Option.allCases.filter { $0.availability == .publicBeta }
    private let developerOptions = BetaFlags.Option.allCases.filter { $0.availability == .developer }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            if isEmpty {
                ContentUnavailableView {
                    Text("No Beta Features")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                } description: {
                    Text("There are no beta features available right now.")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                LazyTable(spacing: 0) {
                    #if DEBUG // LOCAL-TUNER
                    SettingsSectionHeader("Tray Showcase") // LOCAL-TUNER
                    ForEach(TrayKind.allCases) { kind in // LOCAL-TUNER
                        unlinkRow(title: kind.name, isDisabled: false) { showcaseTray = kind } // LOCAL-TUNER
                            .accessibilityIdentifier("tray-showcase-\(kind.rawValue)") // LOCAL-TUNER
                    } // LOCAL-TUNER
                    #endif // LOCAL-TUNER

                    ForEach(publicOptions) { option in
                        BetaFlagToggleRow(option: option, isOn: betaFlags.bindingFor(option: option))
                    }

                    if betaFlags.accessGranted {
                        if !developerOptions.isEmpty {
                            SettingsSectionHeader("Developer")

                            ForEach(developerOptions) { option in
                                BetaFlagToggleRow(option: option, isOn: betaFlags.bindingFor(option: option))
                            }
                        }

                        SettingsSectionHeader("Account")

                        unlinkRow(title: "Unlink Email", isDisabled: session.profile?.email == nil) {
                            isConfirmingUnlinkEmail = true
                        }
                        unlinkRow(title: "Unlink Phone", isDisabled: session.profile?.phone == nil) {
                            isConfirmingUnlinkPhone = true
                        }

                        SettingsSectionHeader("Contracts")

                        ForEach(ContractInfo.all) { info in
                            ContractInfoRow(info: info)
                        }
                    }
                }
            }
        }
        .navigationTitle("Beta Features")
        .toolbarTitleDisplayMode(.inline)
        #if DEBUG // LOCAL-TUNER
        // Each showcase tray comes up over this screen, as it would over any other. // LOCAL-TUNER
        .tray(item: $showcaseTray, isDismissable: showcaseTray?.isDismissable ?? true) { kind in // LOCAL-TUNER
            kind.tray // LOCAL-TUNER
        } // LOCAL-TUNER
        #endif // LOCAL-TUNER
        .alert(
            "Unlink Email?",
            isPresented: $isConfirmingUnlinkEmail
        ) {
            Button("Unlink Email", role: .destructive) {
                Task { await unlinkEmail() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will unlink the email from your account.")
        }
        .alert(
            "Unlink Phone?",
            isPresented: $isConfirmingUnlinkPhone
        ) {
            Button("Unlink Phone", role: .destructive) {
                Task { await unlinkPhone() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will unlink the phone from your account.")
        }
        .alert(
            unlinkAlertTitle ?? "",
            isPresented: $isShowingUnlinkAlert,
            presenting: unlinkAlertMessage
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }

    /// True only when there's nothing at all to show — no public flags, no developer
    /// access to reveal the rest, and so no Contracts section either.
    private var isEmpty: Bool {
        false && // LOCAL-TUNER: the Design section always shows
        !betaFlags.hasVisibleOptions && !betaFlags.accessGranted
    }

    // MARK: - Subviews -

    private func unlinkRow(title: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.appTextMedium)
                    .foregroundStyle(.textMain)
                    .padding([.top, .bottom], 10)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .vSeparator(color: .rowSeparator, position: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    // MARK: - Actions -

    private func unlinkEmail() async {
        guard let email = session.profile?.email else {
            logger.warning("Unlink email invoked but profile has no email")
            return
        }

        do {
            try await container.flipClient.unlinkEmail(email: email, owner: session.ownerKeyPair)
            try? await session.updateProfile()
        } catch {
            showUnlinkAlert(title: "Unlink Failed", message: "\(error)")
        }
    }

    private func unlinkPhone() async {
        guard let phone = session.profile?.phone else {
            logger.warning("Unlink phone invoked but profile has no phone")
            return
        }

        do {
            try await container.flipClient.unlinkPhone(phone: phone.e164, owner: session.ownerKeyPair)
            try? await session.updateProfile()
        } catch {
            showUnlinkAlert(title: "Unlink Failed", message: "\(error)")
        }
    }

    private func showUnlinkAlert(title: String, message: String) {
        unlinkAlertTitle = title
        unlinkAlertMessage = message
        isShowingUnlinkAlert = true
    }
}
