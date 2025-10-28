//
//  WithdrawDescriptionScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct WithdrawDescriptionScreen: View {
    
    @State private var isShowingCurrencySelection: Bool = false
    
    @Binding var isPresented: Bool
    
    @StateObject private var viewModel: WithdrawViewModel
    
    private let container: Container
    private let sessionContainer: SessionContainer
    
    // MARK: - Init -

    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented     = isPresented
        self.container        = container
        self.sessionContainer = sessionContainer
        self._viewModel       = .init(
            wrappedValue: WithdrawViewModel(
                isPresented: isPresented,
                container: container,
                sessionContainer: sessionContainer
            )
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.path) {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 20) {
                    
                    Spacer()
                    
                    Image.asset(.withdrawCircle)
                    
                    Spacer()
                    
                    Text("You can withdraw your funds at any time, and move them into your bank acccount")
                        .font(.appTextMedium)
                        .foregroundColor(.textMain)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                    
                    VStack(spacing: 0) {
                        CodeButton(
                            style: .filled,
                            title: "Withdraw Funds",
                            action: withdrawAction
                        )
                        
                        CodeButton(
                            style: .subtle,
                            title: "Learn How to Withdraw",
                            action: learnAction
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("Withdraw")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WithdrawNavigationPath.self) { path in
                switch path {
                case .enterAmount:
                    WithdrawAmountScreen(viewModel: viewModel)
                case .enterAddress:
                    WithdrawAddressScreen(viewModel: viewModel)
                case .confirmation:
                    WithdrawSummaryScreen(viewModel: viewModel)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .sheet(isPresented: $isShowingCurrencySelection) {
                SelectCurrencyScreen(
                    isPresented: $isShowingCurrencySelection,
                    kind: .select(selectCurrencyAction),
                    fixedRate: .oneToOne,
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
        }
    }
    
    // MARK: - Actions -
    
    private func selectCurrencyAction(exchangeBalance: ExchangedBalance) {
        viewModel.selectedBalance = exchangeBalance
        isShowingCurrencySelection = false
        Task {
            viewModel.pushEnterAmountScreen()
        }
    }
    
    private func withdrawAction() {
        isShowingCurrencySelection.toggle()
    }
    
    private func learnAction() {
        let url = URL(string: "https://chatgpt.com/share/68431512-cdf8-8002-b944-7538e90dfa48")!
        url.openWithApplication()
    }
}
