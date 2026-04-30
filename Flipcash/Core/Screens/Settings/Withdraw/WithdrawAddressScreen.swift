//
//  WithdrawAddressScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-08-04.
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
                        TextField("Enter address", text: $enteredAddress)
                            .font(.appTextMedium)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.leading)
                            .padding([.leading, .trailing], 15)
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
