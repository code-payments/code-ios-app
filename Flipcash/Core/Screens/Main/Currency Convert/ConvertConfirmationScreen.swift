//
//  ConvertConfirmationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct ConvertConfirmationScreen: View {

    @State private var viewModel: ConvertConfirmationViewModel

    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router

    // MARK: - Init -

    init(sourceMint: PublicKey, destinationMint: PublicKey, destinationName: String, amount: ExchangedFiat, sellFeeBps: Int?, pinnedState: VerifiedState) {
        self.viewModel = ConvertConfirmationViewModel(
            sourceMint: sourceMint,
            destinationMint: destinationMint,
            destinationName: destinationName,
            amount: amount,
            sellFeeBps: sellFeeBps,
            pinnedState: pinnedState
        )
    }

    // MARK: - Resolved currency chrome

    private var sourceName: String { session.balance(for: viewModel.sourceMint)?.name ?? "" }
    private var sourceImageURL: URL? { session.balance(for: viewModel.sourceMint)?.imageURL }
    private var destinationImageURL: URL? { session.balance(for: viewModel.destinationMint)?.imageURL }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                Spacer()

                BorderedContainer {
                    VStack(spacing: 0) {
                        ConfirmationAmountRow(
                            title: "You Convert",
                            currencyName: sourceName,
                            imageURL: sourceImageURL,
                            amount: viewModel.totalDebited.nativeAmount.formatted()
                        )
                        .padding(.top, 24)

                        // Every conversion carries a fee: from Dollars it's added
                        // on top of the purchase; otherwise it's taken out of the
                        // converted amount. "Amount to convert" names the purchase
                        // leg in both cases.
                        VStack(spacing: 10) {
                            ConfirmationBreakdownRow(
                                title: "Amount to convert",
                                value: (viewModel.isFromDollars ? viewModel.amountAfterFee : viewModel.amount).nativeAmount.formatted()
                            )
                            ConfirmationBreakdownRow(
                                title: "Conversion fee",
                                value: viewModel.feeFormatted
                            )
                        }
                        .padding()

                        ConfirmationAmountRow(
                            title: "You Receive",
                            currencyName: viewModel.destinationName,
                            imageURL: destinationImageURL,
                            amount: viewModel.amountAfterFee.nativeAmount.formatted()
                        )
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
                        action: performConvert
                    )
                    .padding(.top, 20)
                }
            }
            .padding(20)
        }
        .interactiveDismissDisabled(!viewModel.canDismissSheet)
        .navigationBarBackButtonHidden(viewModel.actionButtonState == .loading)
        .dialog(item: $viewModel.dialogItem)
        .navigationTitle("Convert")
        .toolbarTitleDisplayMode(.inline)
    }

    // MARK: - Actions -

    private func performConvert() {
        viewModel.performConvert(session: session, router: router)
    }
}
