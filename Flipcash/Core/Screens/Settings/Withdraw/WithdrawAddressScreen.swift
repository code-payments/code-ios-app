//
//  WithdrawAddressScreen.swift
//  Code
//
//  Created by Raul Riera on 2026-04-30.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct WithdrawAddressScreen: View {
    let promptCurrencyName: String
    @Binding var enteredAddress: String
    let destinationMetadata: DestinationMetadata?
    let acceptsTokenAccount: Bool
    let canCompleteWithdrawal: Bool
    let onPasteFromClipboard: () -> Void
    let onNext: () -> Void

    @State private var pasteboardObserver = PasteboardObserver()

    private var canPaste: Bool {
        pasteboardObserver.hasStrings
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Where would you like to withdraw your \(promptCurrencyName) to?")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    InputContainer(size: .regular) {
                        TextField("Enter Solana address", text: $enteredAddress)
                            .font(.appTextMedium)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.leading)
                            .padding(.leading, 44)
                            .padding(.trailing, 15)
                            .overlay(alignment: .leading) {
                                Image(.Icons.solana)
                                    .resizable()
                                    .frame(width: 18, height: 14)
                                    .padding(.leading, 15)
                                    .allowsHitTesting(false)
                            }
                    }
                    if let destinationMetadata {
                        WithdrawAddressValidityRow(
                            metadata: destinationMetadata,
                            acceptsTokenAccount: acceptsTokenAccount
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Button("Paste From Clipboard", action: onPasteFromClipboard)
                    .disabled(!canPaste)
                    .buttonStyle(.filled20)

                Spacer()
                    .frame(minHeight: 1)

                Button("Next", action: onNext)
                    .disabled(!canCompleteWithdrawal)
                    .buttonStyle(.filled)
            }
            .padding(20)
        }
        .navigationTitle("Withdraw")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
    }
}
