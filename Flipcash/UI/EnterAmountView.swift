//
//  WithdrawAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-04-05.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

public struct EnterAmountView: View {
    
    @Environment(Session.self) var session
    @Environment(RatesController.self) var rateController
    
    @Binding public var enteredAmount: String
    @Binding public var actionState: ButtonState
    
    private let mode: Mode
    private let subtitle: Subtitle
    private let actionEnabled: (String) -> Bool
    private let action: () -> Void
    private let currencySelectionAction: (() -> Void)?
    
    // MARK: - Calculator -
    
    private var calculator: EnterAmountCalculator {
        EnterAmountCalculator(
            mode: mode,
            entryCurrency: rateController.entryCurrency,
            onrampCurrency: rateController.onrampCurrency,
            sendLimitProvider: session.sendLimitFor(currency:)
        )
    }
    
    // MARK: - Init -
    
    init(
        mode: Mode,
        enteredAmount: Binding<String>,
        subtitle: Subtitle,
        actionState: Binding<ButtonState>,
        actionEnabled: @escaping (String) -> Bool,
        action: @escaping () -> Void,
        currencySelectionAction: (() -> Void)? = nil
    ) {
        self.mode                    = mode
        self.subtitle                = subtitle
        self._enteredAmount          = enteredAmount
        self._actionState            = actionState
        self.actionEnabled           = actionEnabled
        self.action                  = action
        self.currencySelectionAction = currencySelectionAction
    }
    
    // MARK: - Computed -

    private var isExceedingLimit: Bool {
        guard let value = Decimal(string: enteredAmount), value > 0 else {
            return false
        }
        return !actionEnabled(enteredAmount)
    }

    private var subtitleColor: Color {
        isExceedingLimit ? .textError : .textSecondary
    }

    // MARK: - Body -

    public var body: some View {
        VStack(alignment: .center) {
            Spacer()
            
            Button {
                currencySelectionAction?()
            } label: {
                VStack(spacing: 5) {
                    HStack(spacing: 15) {
                        AmountField(
                            content: $enteredAmount,
                            defaultValue: mode.defaultValue,
                            prefix: .flagStyle(calculator.currency.flagStyle),
                            formatter: mode.formatter(with: calculator.currency),
                            suffix: nil,
                            showChevron: currencySelectionAction != nil
                        )
                        .foregroundColor(.textMain)
                    }
                    
                    switch subtitle {
                    case .singleTransactionLimit:
                        if let limit = calculator.maxTransactionAmount {
                            Text("Enter up to \(limit.formatted())")
                                .fixedSize()
                                .foregroundColor(subtitleColor)
                                .font(.appTextMedium)
                        }

                    case .balanceWithLimit(let maxBalance):
                        Text("Enter up to \(calculator.maxEnterAmount(maxBalance: maxBalance).formatted())")
                            .fixedSize()
                            .foregroundColor(subtitleColor)
                            .font(.appTextMedium)

                    case .custom(let text):
                        Text(text)
                            .fixedSize()
                            .foregroundColor(subtitleColor)
                            .font(.appTextMedium)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(currencySelectionAction == nil)
            
            Spacer()
            
            KeyPadView(
                content: $enteredAmount,
                configuration: calculator.currency.maximumFractionDigits > 0 ? .decimal() : .number(),
                rules: KeyPadView.CurrencyRules(
                    maxIntegerDigits: 9,
                    maxDecimalDigits: calculator.currency.maximumFractionDigits
                )
            )
            .padding([.leading, .trailing], -20)
            
            CodeButton(
                state: actionState,
                style: mode.buttonStyle,
                title: mode.actionName,
                disabled: !actionEnabled(enteredAmount),
                action: action
            )
            .padding(.top, 10)
        }
    }
}

// MARK: - Mode -

extension EnterAmountView {
    enum Mode {

        case phantomDeposit
        case walletDeposit(String)
        case currency
        case onramp
        case withdraw
        case buy
        case sell

        fileprivate func formatter(with currency: CurrencyCode) -> NumberFormatter {
            switch self {
            case .currency, .onramp, .walletDeposit, .phantomDeposit, .withdraw, .buy, .sell:
                return .fiat(currency: currency, minimumFractionDigits: 0)
            }
        }

        fileprivate var defaultValue: AmountField.DefaultValue {
            switch self {
            case .currency, .onramp, .walletDeposit, .phantomDeposit, .withdraw, .buy, .sell: return .number("0")
            }
        }

        fileprivate var actionName: String {
            switch self {
            case .phantomDeposit:
                return "Confirm In"
            case .walletDeposit(let walletName):
                return "Confirm In \(walletName)"
            case .currency: return "Next"
            case .onramp:   return "Add Cash"
            case .withdraw: return "Next"
            case .buy:      return "Buy"
            case .sell:     return "Next"
            }
        }

        fileprivate var buttonStyle: CodeButton.Style {
            switch self {
            case .phantomDeposit: return .filledCustom(Image.asset(.phantom), "Phantom")
            case .walletDeposit:  return .filled
            case .currency:       return .filled
            case .onramp:         return .filledApplePay
            case .withdraw:       return .filled
            case .buy:            return .filled
            case .sell:           return .filled
            }
        }
    }
}

// MARK: - Subtitle -

extension EnterAmountView {
    enum Subtitle {
        case singleTransactionLimit
        case balanceWithLimit(ExchangedFiat)
        case custom(String)
    }
}

// MARK: - Previews -

#Preview {
    EnterAmountView(
        mode: .currency,
        enteredAmount: .constant("123"),
        subtitle: .singleTransactionLimit,
        actionState: .constant(.normal),
        actionEnabled: { _ in return true }
    ) {}
}
