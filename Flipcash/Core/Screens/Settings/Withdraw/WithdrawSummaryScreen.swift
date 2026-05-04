//
//  WithdrawSummaryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct WithdrawSummaryScreen: View {

    @Bindable var viewModel: WithdrawViewModel

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                if let entered = viewModel.enteredFiat,
                   let net = viewModel.displayNet,
                   let display = viewModel.youReceiveDisplayValue {
                    BorderedContainer {
                        VStack(spacing: 20) {
                            VStack(spacing: 16) {
                                SummaryLineItem(
                                    title: "Withdrawal amount",
                                    value: entered.nativeAmount.formatted()
                                )
                                SummaryLineItem(
                                    title: "Less fee",
                                    value: viewModel.displayFee.map { "-\($0.formatted())" } ?? "—"
                                )
                                SummaryLineItem(
                                    title: "Net amount",
                                    value: net.formatted()
                                )
                                if let kind = viewModel.kind {
                                    SummaryLineItem(
                                        title: "Amount in \(kind.destinationCurrencyName)",
                                        value: display
                                    )
                                }
                            }

                            YouReceiveSection(
                                logoURL: viewModel.destinationLogoURL,
                                displayValue: display
                            )
                            .padding(.top, 20)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("You receive \(display) in \(viewModel.kind?.destinationCurrencyName ?? "tokens")")
                        }
                        .padding(20)
                    }
                }
                
                Image.system(.arrowDown)
                    .foregroundStyle(Color.textSecondary)

                AddressDestinationBox(address: viewModel.enteredDestination?.base58 ?? "")
                    .accessibilityLabel(viewModel.enteredAddress)

                Spacer()

                CodeButton(
                    state: viewModel.withdrawButtonState,
                    style: .filled,
                    title: "Withdraw",
                    action: viewModel.completeWithdrawalAction
                )
            }
            .padding(20)
        }
        .navigationTitle("Withdraw")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
    }
}

private struct SummaryLineItem: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.textMain)
        }
        .font(.appTextSmall)
    }
}

private struct YouReceiveSection: View {
    let logoURL: URL?
    let displayValue: String

    var body: some View {
        VStack(spacing: 12) {
            Text("You Receive")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 8) {
                RemoteImage(url: logoURL)
                    .frame(width: 32, height: 32)
                    .clipShape(.circle)
                Text(displayValue)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AddressDestinationBox: View {
    let address: String

    var body: some View {
        BorderedContainer {
            Text(address)
                .font(.appDisplayXS)
                .multilineTextAlignment(.center)
                .padding(20)
        }
    }
}
