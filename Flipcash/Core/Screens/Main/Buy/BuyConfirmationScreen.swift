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
                            title: "You Get",
                            currencyName: viewModel.targetName,
                            imageURL: viewModel.targetImageURL,
                            amount: viewModel.amountToBuy.nativeAmount.formatted()
                        )
                        .padding(.top, 24)

                        if viewModel.chargesFee {
                            VStack(spacing: 10) {
                                ConfirmationBreakdownRow(
                                    title: "Amount to convert",
                                    value: viewModel.amountToBuy.nativeAmount.formatted()
                                )
                                ConfirmationBreakdownRow(
                                    title: "Conversion fee",
                                    value: viewModel.feeFormatted
                                )
                            }
                            .padding()
                        }

                        ConfirmationAmountRow(
                            title: "You Pay",
                            currencyName: viewModel.payment.name,
                            imageURL: viewModel.payment.imageURL,
                            amount: viewModel.grossDebit.nativeAmount.formatted()
                        )
                        .padding(.top, viewModel.chargesFee ? 0 : 24)
                        .padding(.bottom, 24)
                    }
                }

                Spacer()

                VStack {
                    Text("Review the above before confirming.\nOnce made, your transaction is irreversible.")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    CodeButton(
                        state: viewModel.actionButtonState,
                        style: .filled,
                        title: "Confirm",
                        disabled: !viewModel.canPerformAction,
                        action: performBuy
                    )
                    .accessibilityIdentifier("buy-confirmation-buy")
                    .padding(.top, 20)
                }
            }
            .padding(20)
        }
        .navigationTitle("Get")
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
