//
//  WithdrawAddressScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-08-04.
//

import SwiftUI
import CodeUI
import CodeServices

struct WithdrawAddressScreen: View {
    
    @ObservedObject private var viewModel: WithdrawViewModel
    
    @State private var isPresentingSummary = false
    
    // MARK: - Init -
    
    init(viewModel: WithdrawViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 20) {
                NavigationLink(isActive: $isPresentingSummary) {
                    LazyView(
                        WithdrawSummaryScreen(viewModel: viewModel)
                    )
                } label: {
                    EmptyView()
                }
                
                Text(Localized.Subtitle.whereToWithdrawKin)
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                
                VStack(spacing: 10) {
                    InputContainer(size: .regular) {
                        TextField(Localized.Subtitle.enterDestinationAddress, text: $viewModel.enteredAddress)
                            .font(.appTextMedium)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.leading)
                            .padding([.leading, .trailing], 15)
                            .onChange(of: viewModel.enteredAddress) { newValue in
                                viewModel.addressDidChange()
                            }
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
                    title: Localized.Action.pasteFromClipboard,
                    disabled: !viewModel.canAttemptPasteAddress
                ) {
                    _ = viewModel.attemptPasteAddressFromClipboard()
                }
                
                Spacer()
                
                CodeButton(
                    style: .filled,
                    title: Localized.Action.next,
                    disabled: !viewModel.readyToSend
                ) {
                    isPresentingSummary = true
                }
            }
            .padding(20)
        }
        .navigationBarTitle(Text(Localized.Title.withdrawKin), displayMode: .inline)
        .onAppear {
            Analytics.open(screen: .withdrawAddress)
            ErrorReporting.breadcrumb(.withdrawAddressScreen)
        }
    }
    
    @ViewBuilder private func message(for metadata: DestinationMetadata) -> some View {
        switch metadata.kind {
        case .unknown:
            HStack(spacing: 6) {
                Image.system(.xmark)
                Text(Localized.Subtitle.invalidTokenAccount)
                    .lineLimit(1)
            }
            .font(.appTextCaption)
            .foregroundColor(.textError)
            
        case .owner, .token:
            HStack(spacing: 6) {
                Image.system(.circleCheck)
                Group {
                    if metadata.hasResolvedDestination {
                        Text(Localized.Subtitle.validOwnerAccount)
//                        Text("Resolved to")
//                        Text(metadata.resolvedDestination.base58)
//                            .truncationMode(.middle)
                    } else {
                        Text(Localized.Subtitle.validTokenAccount)
                    }
                }
                .lineLimit(1)
                
            }
            .font(.appTextCaption)
            .foregroundColor(.textSuccess)
        }
    }
}

// MARK: - Previews -

struct WithdrawAddressScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WithdrawAddressScreen(
                viewModel: WithdrawViewModel(
                    session: .mock,
                    exchange: .mock,
                    biometrics: .mock
                )
            )
        }
        .environmentObjectsForSession()
    }
}
