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
    
    @ObservedObject private var viewModel: WithdrawViewModel
    
    @State private var pasteboardObserver = PasteboardObserver()
    
    private var canPaste: Bool {
        pasteboardObserver.hasStrings
    }
    
    // MARK: - Init -
    
    init(viewModel: WithdrawViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Where would you like to withdraw your USDC to?")
                    .font(.appTextMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                VStack(spacing: 10) {
                    InputContainer(size: .regular) {
                        TextField("Enter address", text: $viewModel.enteredAddress)
                            .font(.appTextMedium)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.leading)
                            .padding([.leading, .trailing], 15)
                    }
                    if let metadata = viewModel.destinationMetadata {
                        VStack {
                            message(for: metadata)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                CodeButton(
                    style: .filled,
                    title: "Paste From Clipboard",
                    disabled: !canPaste,
                    action: viewModel.pasteFromClipboardAction
                )
                
                Spacer()
                    .frame(minHeight: 1)
                
                CodeButton(
                    style: .filled,
                    title: "Next",
                    disabled: !viewModel.canCompleteWithdrawal,
                    action: viewModel.addressEnteredAction
                )
            }
            .padding(20)
        }
        .navigationTitle("Withdraw")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
    }
    
    @ViewBuilder private func message(for metadata: DestinationMetadata) -> some View {
        switch metadata.kind {
        case .unknown:
            HStack(alignment: .top, spacing: 6) {
                Image.system(.xmark)
                Text("Destination address not valid")
                    .lineLimit(1)
            }
            .font(.appTextHeading)
            .foregroundColor(.textError)
            
        case .owner, .token:
            HStack(spacing: 6) {
                Image.system(.circleCheck)
                Text("Valid address")
                    .lineLimit(1)
            }
            .font(.appTextHeading)
            .foregroundColor(.textSuccess)
        }
    }
}
