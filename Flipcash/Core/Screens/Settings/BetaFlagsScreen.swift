//
//  BetaFlagsScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-25.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.betaflags")

struct BetaFlagsScreen: View {

    @Bindable private var betaFlags: BetaFlags

    @Environment(Session.self) private var session

    @State private var isConfirmingUnlinkEmail: Bool = false
    @State private var isConfirmingUnlinkPhone: Bool = false
    @State private var unlinkAlertTitle: String?
    @State private var unlinkAlertMessage: String?
    @State private var isShowingUnlinkAlert: Bool = false

    private let container: Container

    // MARK: - Init -

    init(container: Container) {
        self.betaFlags = container.betaFlags
        self.container = container
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            LazyTable(spacing: 0) {
                sectionHeader("Flags")

                ForEach(BetaFlags.Option.allCases) { option in
                    HStack(spacing: 12) {
                        Toggle(isOn: betaFlags.bindingFor(option: option)) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(option.localizedTitle)
                                    .foregroundStyle(.textMain)
                                    .font(.appTextMedium)
                                Text(option.localizedDescription)
                                    .foregroundStyle(.textSecondary)
                                    .font(.appTextHeading)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.trailing, 20)
                        }
                        .tint(.textSuccess)
                    }
                    .padding(20)
                    .vSeparator(color: .rowSeparator, position: .bottom)
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
        .navigationTitle("Beta Flags")
        .navigationBarTitleDisplayMode(.inline)
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

extension BetaFlagsScreen {
    struct Option {
        var title: String
        var description: String
        var binding: Binding<Bool>
    }
}
