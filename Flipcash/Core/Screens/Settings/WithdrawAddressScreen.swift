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
            VStack(alignment: .center, spacing: 10) {
                Text("Where would you like to withdraw $20 CAD of USDC to?")
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
                
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
                .padding(.top, 5)
                
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
                VStack(alignment: .leading, spacing: 5) {
                    Text("Destination Account Not Initialized")
                        .lineLimit(1)
                        .font(.appTextHeading)
                    Text("Please make sure the address you’re withdrawing to has been initialized by your wallet provider. A quick way to do this is to make sure there is already some USDC in the address you’re trying to withdraw to.")
                        .font(.appTextCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 1)
            }
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
