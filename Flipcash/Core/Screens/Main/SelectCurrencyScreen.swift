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

    let fixedRate: Rate?
    let action: (ExchangedBalance) -> Void

    private var balances: [ExchangedBalance] {
        session.balances(for: fixedRate ?? ratesController.rateForBalanceCurrency())
            .filter { $0.stored.mint != .usdf }
    }

    init(
        isPresented: Binding<Bool>,
        fixedRate: Rate? = nil,
        action: @escaping (ExchangedBalance) -> Void
    ) {
        self._isPresented = isPresented
        self.fixedRate = fixedRate
        self.action = action
    }

    var body: some View {
        // Cache the body-time computed property so `if balances.isEmpty` and
        // `ForEach(balances)` don't each re-run `session.balances(for:).filter`.
        let balances = self.balances

        NavigationStack {
            Background(color: .backgroundMain) {
                if balances.isEmpty {
                    Text("No currencies to give")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 40)
                        .accessibilityIdentifier("give-picker-empty")
                } else {
                    List {
                        Section {
                            ForEach(balances) { balance in
                                CurrencyBalanceRow(
                                    exchangedBalance: balance,
                                    accessory: .check(isSelected: ratesController.isSelectedToken(balance.stored.mint)),
                                    amountStyle: .pill
                                ) {
                                    action(balance)
                                    isPresented = false
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Select Currency")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(binding: $isPresented)
                }
            }
        }
    }
}

enum CurrencyRowAccessory {
    case chevron
    case check(isSelected: Bool)
}

struct CurrencyBalanceRow: View {

    let exchangedBalance: ExchangedBalance
    let accessibilityIdentifier: String
    let action: (() -> Void)?
    let accessory: CurrencyRowAccessory?
    let amountStyle: CurrencyLabel.AmountStyle
    let usesSymbol: Bool

    init(
        exchangedBalance: ExchangedBalance,
        accessibilityIdentifier: String = "currency-row",
        accessory: CurrencyRowAccessory? = nil,
        amountStyle: CurrencyLabel.AmountStyle = .plain,
        usesSymbol: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.exchangedBalance = exchangedBalance
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessory = accessory
        self.amountStyle = amountStyle
        self.usesSymbol = usesSymbol
        self.action = action
    }

    var body: some View {
        Button {
            action?()
        } label: {
            CurrencyLabel(
                imageURL: exchangedBalance.stored.imageURL,
                name: usesSymbol ? exchangedBalance.stored.symbol : exchangedBalance.stored.name,
                amount: exchangedBalance.exchangedFiat.nativeAmount,
                amountStyle: amountStyle,
                accessory: accessory
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
    var amountStyle: AmountStyle = .plain
    var accessory: CurrencyRowAccessory? = nil

    enum AmountStyle {
        case plain
        case pill
    }

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
                AmountLabel(amount: amount, style: amountStyle)
            }

            if let accessory {
                AccessoryView(accessory: accessory)
                    .accessibilityHidden(true)
                    .padding(.leading, 12)
            }
        }
    }
}

private struct AmountLabel: View {

    let amount: FiatAmount
    let style: CurrencyLabel.AmountStyle

    var body: some View {
        Group {
            switch style {
            case .plain:
                Text(amount.formatted())
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
            case .pill:
                Text(amount.formatted())
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .inset(by: 0.5)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .contentTransition(.numericText())
        .animation(.default, value: amount)
    }
}

private struct AccessoryView: View {

    let accessory: CurrencyRowAccessory

    var body: some View {
        switch accessory {
        case .chevron:
            Image.system(.chevronRight)
                .foregroundStyle(Color.textSecondary)
        case .check(let isSelected):
            CheckView(active: isSelected)
        }
    }
}
