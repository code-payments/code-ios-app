//
//  SelectCurrencyScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-10-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SelectCurrencyScreen<Header: View>: View {

    @Binding var isPresented: Bool

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController

    let action: (ExchangedBalance) -> Void
    let isEnabled: (ExchangedBalance) -> Bool
    let isSelected: ((ExchangedBalance) -> Bool)?
    private let header: Header?
    private let listTitle: String?

    private var balances: [ExchangedBalance] {
        session.balances(for: ratesController.rateForBalanceCurrency())
            .giveable()
    }

    /// Creates a picker with `header` drawn above the currency list, and `listTitle` labelling the
    /// list beneath it.
    ///
    /// The header spans the list's full width and sets its own margins. It stays on screen when
    /// there is nothing giveable to list, since it is a choice of its own rather than one of the
    /// list's rows.
    ///
    /// - Parameter isSelected: which row draws its checkmark. Defaults to the currency the wallet is
    ///   denominated in, which is what picking one here changes. Pass a closure when the screen is
    ///   picking for something else — a group chat's balance requirement, say — so the check follows
    ///   that choice instead of the wallet's.
    init(
        isPresented: Binding<Bool>,
        isEnabled: @escaping (ExchangedBalance) -> Bool = { _ in true },
        isSelected: ((ExchangedBalance) -> Bool)? = nil,
        listTitle: String,
        action: @escaping (ExchangedBalance) -> Void,
        @ViewBuilder header: () -> Header
    ) {
        self._isPresented = isPresented
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.action = action
        self.header = header()
        self.listTitle = listTitle
    }

    var body: some View {
        // Cache the body-time computed property so `if balances.isEmpty` and
        // `ForEach(balances)` don't each re-run `session.balances(for:).filter`.
        let balances = self.balances

        NavigationStack {
            Background(color: .backgroundMain) {
                if balances.isEmpty && header == nil {
                    Text("No currencies to give")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 40)
                        .accessibilityIdentifier("give-picker-empty")
                } else {
                    List {
                        if let header {
                            header
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            if let listTitle, !balances.isEmpty {
                                Text(listTitle)
                                    .font(.default(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.textMain.opacity(0.5))
                                    .padding(.top, 24)
                                    .padding(.bottom, 4)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }

                        Section {
                            ForEach(balances) { balance in
                                let enabled = isEnabled(balance)
                                CurrencyBalanceRow(
                                    exchangedBalance: balance,
                                    accessory: .check(
                                        isSelected: isSelected?(balance)
                                            ?? ratesController.isSelectedToken(balance.stored.mint)
                                    ),
                                    amountStyle: .pill
                                ) {
                                    action(balance)
                                    isPresented = false
                                }
                                .disabled(!enabled)
                                .opacity(enabled ? 1 : 0.4)
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

extension SelectCurrencyScreen where Header == EmptyView {

    /// Creates a picker listing only the giveable currencies.
    ///
    /// - Parameter isSelected: which row draws its checkmark. Defaults to the currency the wallet is
    ///   denominated in, which is what picking one here changes.
    init(
        isPresented: Binding<Bool>,
        isEnabled: @escaping (ExchangedBalance) -> Bool = { _ in true },
        isSelected: ((ExchangedBalance) -> Bool)? = nil,
        action: @escaping (ExchangedBalance) -> Void
    ) {
        self._isPresented = isPresented
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.action = action
        self.header = nil
        self.listTitle = nil
    }
}

enum CurrencyRowAccessory {
    case chevron
    case check(isSelected: Bool)
    case loader
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
                    .font(.appTextHeading)
                    .foregroundStyle(Color.textSecondary)
                    .padding(4)
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
        case .loader:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.textSecondary)
        }
    }
}
