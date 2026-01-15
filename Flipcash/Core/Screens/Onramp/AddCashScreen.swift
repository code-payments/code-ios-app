//
//  AddCashScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct AddCashScreen: View {
    
    @Binding var isPresented: Bool
    
    @ObservedObject private var viewModel: OnrampViewModel
    @ObservedObject private var walletConnection: WalletConnection
    
    @State private var isShowingDepositScreen: Bool = false
    
    private let container: Container
    private let sessionContainer: SessionContainer
    private let session: Session
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented     = isPresented
        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        self.viewModel        = sessionContainer.onrampViewModel
        self.walletConnection = sessionContainer.walletConnection
    }
    
    // MARK: - Body -
    
    var body: some View {
        alternateView()
    }
    
    @ViewBuilder private func primaryView() -> some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 20) {
                    if session.userFlags?.hasCoinbase == true {
                        row(
                            image: .debitCard,
                            name: "Apple Pay",
                            action: viewModel.addCashWithDebitCardAction
                        )
                    }
                    
                    if session.userFlags?.hasPhantom == true {
                        row(
                            image: .phantom,
                            name: "Phantom",
                            action: walletConnection.connectToPhantom
                        )
                    }
                    
                    row(
                        image: .debitWallet,
                        name: "Crypto Wallet"
                    ) {
                        isShowingDepositScreen = true
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Deposit Solana USDC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .navigationDestination(isPresented: $isShowingDepositScreen) {
                DepositDescriptionScreen(
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
            .sheet(isPresented: $walletConnection.isShowingAmountEntry) {
                NavigationStack {
                    EnterWalletAmountScreen { quarks in
                        try await walletConnection.requestTransfer(usdf: quarks)
                        walletConnection.isShowingAmountEntry = false
                    }
                    .toolbar {
                        ToolbarCloseButton(binding: $walletConnection.isShowingAmountEntry)
                    }
                }
            }
            .dialog(item: $walletConnection.dialogItem)
        }
    }
    
    @ViewBuilder private func row(image: Asset, name: String, action: @escaping VoidAction) -> some View {
        let insets = EdgeInsets(
            top: 25,
            leading: 0,
            bottom: 25,
            trailing: 0
        )
        
        Row(insets: insets) {
            Image.asset(image)
                .frame(minWidth: 45)
            Text(name)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
            Spacer()
        } action: {
            action()
        }
        .font(.appDisplayXS)
    }
    
    @ViewBuilder private func alternateView() -> some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(alignment: .center) {
                    VStack(spacing: 40) {
                        
                        // Header
                        VStack(spacing: 30) {
                            Image.asset(.solanaUSDC)
                                // Offset the Solana badge on the bottom right
                                .padding(.leading, 15)
                            
                            Text("Add Solana USDC to your Flipcash wallet")
                                .font(.appTextMedium)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // Buttons
                        VStack(spacing: 15) {
                            if session.userFlags?.hasCoinbase == true {
                                BorderedButton(
                                    image: .asset(.debitCard),
                                    title: "Apple Pay",
                                    subtitle: nil,//"Add cash to your wallet from your debit card",
                                    action: viewModel.addCashWithDebitCardAction
                                )
                            }
                            
                            if session.userFlags?.hasPhantom == true {
                                BorderedButton(
                                    image: .asset(.phantom),
                                    title: "Phantom Wallet",
                                    subtitle: nil,//"Deposit USDC from your Phantom wallet",
                                    action: walletConnection.connectToPhantom
                                )
                            }
                            
                            BorderedButton(
                                image: .asset(.debitWallet),
                                title: "Manual Deposit",
                                subtitle: nil,//"Deposit USDC from your crypto wallet"
                            ) {
                                isShowingDepositScreen = true
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 50)
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Deposit Solana USDC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .navigationDestination(isPresented: $isShowingDepositScreen) {
                DepositDescriptionScreen(
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
            .sheet(isPresented: $walletConnection.isShowingAmountEntry) {
                NavigationStack {
                    EnterWalletAmountScreen { quarks in
                        try await walletConnection.requestTransfer(usdf: quarks)
                        walletConnection.isShowingAmountEntry = false
                    }
                    .toolbar {
                        ToolbarCloseButton(binding: $walletConnection.isShowingAmountEntry)
                    }
                }
            }
            .dialog(item: $walletConnection.dialogItem)
        }
    }
}
