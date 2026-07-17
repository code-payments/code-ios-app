//
//  BuyConfirmationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct BuyConfirmationScreen: View {

    @State private var viewModel: BuyConfirmationViewModel

    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session

    init(targetMint: PublicKey, targetName: String, payment: StoredBalance, paymentAmount: ExchangedFiat, pinnedState: VerifiedState) {
        self._viewModel = State(initialValue: BuyConfirmationViewModel(
            targetMint: targetMint,
            targetName: targetName,
            payment: payment,
            paymentAmount: paymentAmount,
            pinnedState: pinnedState
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Background(color: .backgroundMain) {
            VStack {
                Spacer()

                BorderedContainer {
                    VStack(spacing: 0) {
                        ConfirmationAmountRow(
                            title: "You Pay",
                            currencyName: viewModel.payment.name,
                            imageURL: viewModel.payment.imageURL,
                            amount: viewModel.paymentAmount.nativeAmount.formatted()
                        )
                        .padding(.top, 24)

                        if !viewModel.isUSDF {
                            VStack(spacing: 10) {
                                ConfirmationBreakdownRow(
                                    title: "Amount to buy",
                                    value: viewModel.amountToBuy.nativeAmount.formatted()
                                )
                                ConfirmationBreakdownRow(
                                    title: "Exchange fee",
                                    value: viewModel.feeFormatted
                                )
                            }
                            .padding()
                        }

                        ConfirmationAmountRow(
                            title: "You Receive",
                            currencyName: viewModel.targetName,
                            imageURL: viewModel.targetImageURL,
                            amount: viewModel.amountToBuy.nativeAmount.formatted()
                        )
                        .padding(.top, viewModel.isUSDF ? 24 : 0)
                        .padding(.bottom, 24)
                    }
                }

                Spacer()

                CodeButton(
                    state: viewModel.actionButtonState,
                    style: .filled,
                    title: "Buy",
                    disabled: !viewModel.canPerformAction,
                    action: performBuy
                )
                .accessibilityIdentifier("buy-confirmation-buy")
            }
            .padding(20)
        }
        .navigationTitle("Buy")
        .toolbarTitleDisplayMode(.inline)
        // A submit is a live money movement — keep the user on this screen
        // until it resolves (the sheet's swipe-dismiss is already blocked at
        // the stack root while any step is pushed).
        .navigationBarBackButtonHidden(viewModel.actionButtonState == .loading)
        .dialog(item: $viewModel.dialogItem)
        .task { await viewModel.loadTargetImage(session: session) }
    }

    // MARK: - Actions -

    private func performBuy() {
        Task { await viewModel.buyAction(session: session, router: router) }
    }
}

/// A centered label-over-amount block with the currency's icon, used for the
/// You Pay / You Receive rows.
private struct ConfirmationAmountRow: View {
    let title: String
    let currencyName: String
    let imageURL: URL?
    let amount: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 8) {
                if let imageURL {
                    RemoteImage(url: imageURL)
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                }
                Text(amount)
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
            }
        }
        // The icon is the only visual carrier of WHICH currency this is —
        // VoiceOver needs the name spoken alongside the amount.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(amount) of \(currencyName)")
    }
}

/// A leading title / trailing value line for the fee breakdown.
private struct ConfirmationBreakdownRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
        }
    }
}
