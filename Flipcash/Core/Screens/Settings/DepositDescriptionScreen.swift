//
//  DepositDescriptionScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct DepositDescriptionScreen: View {
    
    @State private var isShowingDeposit: Bool           = false
    @State private var isShowingCurrencySelection: Bool = false
    
    @State private var selectedBalance: ExchangedBalance?
    
    private let container: Container
    private let sessionContainer: SessionContainer
    private let session: Session
    private let database: Database
    
    // MARK: - Init -
    
    init(container: Container, sessionContainer: SessionContainer) {
        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        self.database         = sessionContainer.database
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 20) {
                NavigationLink(isActive: $isShowingDeposit) {
                    if let balance = selectedBalance {
                        DepositScreen(
                            cluster: depositCluster(for: balance.stored),
                            name: balance.stored.name
                        )
                    } else {
                        EmptyView()
                    }
                } label: { EmptyView() }
                
                Spacer()
                
                Image.asset(.depositCircle)
                
                Spacer()
                
                Text("Purchase USDC on a crypto exchange with your bank account, and then deposit into Flipcash")
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                VStack(spacing: 0) {
                    CodeButton(
                        style: .filled,
                        title: "Deposit USDC",
                        action: depositAction
                    )
                    
                    CodeButton(
                        style: .subtle,
                        title: "Learn How to Get USDC",
                        action: learnAction
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .navigationTitle("Deposit")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingCurrencySelection) {
            SelectCurrencyScreen(
                isPresented: $isShowingCurrencySelection,
                kind: .select(selectCurrencyAction),
                container: container,
                sessionContainer: sessionContainer
            )
        }
    }
    
    private func depositCluster(for balance: StoredBalance) -> AccountCluster {
        session.owner.use(
            mint: balance.mint,
            timeAuthority: balance.vmAuthority!
        )
    }
    
    // MARK: - Actions -
    
    private func selectCurrencyAction(exchangeBalance: ExchangedBalance) {
        selectedBalance = exchangeBalance
        isShowingCurrencySelection = false
        Task {
            isShowingDeposit = true
        }
    }
    
    private func depositAction() {
        isShowingCurrencySelection.toggle()
    }
    
    private func learnAction() {
        let url = URL(string: "https://chatgpt.com/share/68431710-5824-8002-af0a-c4948970b626")!
        url.openWithApplication()
    }
}
