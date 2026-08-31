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
                    ForEach(publicOptions) { option in
                        BetaFlagToggleRow(option: option, isOn: betaFlags.bindingFor(option: option))
                    }

                    if betaFlags.accessGranted {
                        if !developerOptions.isEmpty {
                            sectionHeader("Developer")

                            ForEach(developerOptions) { option in
                                BetaFlagToggleRow(option: option, isOn: betaFlags.bindingFor(option: option))
                            }
                        }

                        sectionHeader("Account")

                        unlinkRow(title: "Unlink Email", isDisabled: session.profile?.email == nil) {
                            isConfirmingUnlinkEmail = true
                        }
                        unlinkRow(title: "Unlink Phone", isDisabled: session.profile?.phone == nil) {
                            isConfirmingUnlinkPhone = true
                        }
                    }
                }
                .softScrollEdge(for: .top)
            }
        }
        .navigationTitle("Beta Features")
        .toolbarTitleDisplayMode(.inline)
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

    /// True only when there's nothing at all to show — no public flags, and no
    /// developer access to reveal the rest.
    private var isEmpty: Bool {
        !betaFlags.hasVisibleOptions
    }

    // MARK: - Subviews -

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.appTextHeading)
                .foregroundStyle(.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

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
