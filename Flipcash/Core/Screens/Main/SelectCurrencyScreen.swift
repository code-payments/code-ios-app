//
//  SelectCurrencyScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-10-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SelectCurrencyScreen: View {
    
    @Binding var isPresented: Bool
    
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
        
    @State private var selectedBalance: ExchangedBalance?
    
    private var balances: [ExchangedBalance] {
        let allBalances = session.balances(for: fixedRate ?? ratesController.rateForBalanceCurrency())
        switch kind {
        case .give:
            return allBalances.filter { $0.stored.mint != .usdf }
        case .select:
            return allBalances
        }
    }
    
    private func shouldShowSelected(_ balance: ExchangedBalance) -> Bool? {
        if case .give = kind {
            return ratesController.isSelectedToken(balance.stored.mint)
        }
        return nil
    }
    
    let kind: Kind
    let fixedRate: Rate?
    
    // MARK: - Init -
    init(isPresented: Binding<Bool>, kind: Kind, fixedRate: Rate?) {
        self._isPresented        = isPresented
        self.kind                = kind
        self.fixedRate           = fixedRate
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                List {
                    Section {
                        ForEach(balances) { balance in
                            CurrencyBalanceRow(
                                exchangedBalance: balance,
                                showSelected: shouldShowSelected(balance),
                            ) {
                                switch kind {
                                case .give(let action):
                                    action(balance)
                                    isPresented = false
                                    
                                case .select(let action):
                                    action(balance)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(binding: $isPresented)
                }
            }
        }
    }
}

extension SelectCurrencyScreen {
    enum Kind {
        case give((ExchangedBalance) -> Void)
        case select((ExchangedBalance) -> Void)
    }
}

struct CurrencyBalanceRow: View {

    let exchangedBalance: ExchangedBalance
    let accessibilityIdentifier: String
    let action: (() -> Void)?
    let showSelected: Bool?

    init(
        exchangedBalance: ExchangedBalance,
        accessibilityIdentifier: String = "currency-row",
        showSelected: Bool? = nil,
        action: (() -> Void)? = nil
    ) {
        self.exchangedBalance = exchangedBalance
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
        self.showSelected = showSelected
    }

    var body: some View {
        Button {
            action?()
        } label: {
            CurrencyLabel(
                imageURL: exchangedBalance.stored.imageURL,
                name: exchangedBalance.stored.name,
                amount: exchangedBalance.exchangedFiat.nativeAmount,
                isSelected: showSelected,
            )
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .disabled(action == nil)
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
}

struct CurrencyLabel: View {
    
    let imageURL: URL?
    let name: String
    let amount: FiatAmount?
    var isSelected: Bool? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            if let imageURL {
                RemoteImage(url: imageURL)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            }
            
            Text(name)
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)

            if let amount {
                Spacer()

                Text(amount.formatted())
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .contentTransition(.numericText())
                    .animation(.default, value: amount)
            }

            if let isSelected {
                CheckView(active: isSelected)
                    .padding(.leading, 12)
            }
        }
    }
}
