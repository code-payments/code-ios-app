//
//  DepositScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct DepositScreen: View {
    @State private var buttonState: ButtonState = .normal

    private let address: String
    private let name: String?

    init(address: String, name: String?) {
        self.address = address
        self.name = name
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Deposit funds into your wallet by sending \(name ?? "funds") to your deposit address below. Tap to copy.")
                    .font(.appTextMedium)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    copyAddress()
                } label: {
                    ImmutableField(address, leadingIcon: Image(.Icons.solana))
                }

                Spacer()

                CodeButton(
                    state: buttonState,
                    style: .filled,
                    title: "Copy Address",
                    action: copyAddress
                )
            }
            .padding(20)
        }
        .navigationTitle(name.map { "Deposit \($0)" } ?? "Deposit")
        .toolbarTitleDisplayMode(.inline)
    }

    private func copyAddress() {
        UIPasteboard.general.string = address
        buttonState = .successText("Copied")
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            buttonState = .normal
        }
    }
}

// MARK: - Deposit sources

extension DepositScreen {

    /// The owner's USDC deposit screen — the authority pubkey, NOT the
    /// derived ATA. Showing the ATA breaks first-time deposits: it doesn't
    /// exist on-chain yet, so wallets derive another ATA and funds land one
    /// level deeper than the server queries.
    static func usdcDeposit(session: Session) -> DepositScreen {
        DepositScreen(address: session.owner.authorityPublicKey.base58, name: "USDC")
    }

    /// The deposit screen for `mint`'s derived deposit ATA, or `nil` when
    /// the balance or VM authority isn't loaded.
    static func currencyDeposit(mint: PublicKey, session: Session) -> DepositScreen? {
        guard let balance = session.balance(for: mint),
              let vmAuthority = balance.vmAuthority else { return nil }
        return DepositScreen(
            address: session.owner.use(mint: mint, timeAuthority: vmAuthority).depositPublicKey.base58,
            name: mint == .usdf ? balance.symbol : balance.name
        )
    }
}
