//
//  EnterAmountView.swift
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
    private let actionOverride: AnyView?
    private let actionTitle: String?

    // MARK: - Calculator -
    
    private var calculator: EnterAmountCalculator {
        EnterAmountCalculator(
            mode: mode,
            selectedCurrency: rateController.balanceCurrency,
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
        currencySelectionAction: (() -> Void)? = nil,
        actionTitle: String? = nil
    ) {
        self.mode                    = mode
        self.subtitle                = subtitle
        self._enteredAmount          = enteredAmount
        self._actionState            = actionState
        self.actionEnabled           = actionEnabled
        self.action                  = action
        self.currencySelectionAction = currencySelectionAction
        self.actionOverride          = nil
        self.actionTitle             = actionTitle
    }

    /// Variant where the caller supplies the bottom action control (e.g.
    /// `SwipeControl`) instead of the default `CodeButton`. The control inherits
    /// the same disabled gating via `actionEnabled`.
    init<ActionContent: View>(
        mode: Mode,
        enteredAmount: Binding<String>,
        subtitle: Subtitle,
        actionEnabled: @escaping (String) -> Bool,
        currencySelectionAction: (() -> Void)? = nil,
        @ViewBuilder actionContent: () -> ActionContent
    ) {
        self.mode                    = mode
        self.subtitle                = subtitle
        self._enteredAmount          = enteredAmount
        self._actionState            = .constant(.normal)
        self.actionEnabled           = actionEnabled
        self.action                  = {}
        self.currencySelectionAction = currencySelectionAction
        self.actionOverride          = AnyView(actionContent())
        self.actionTitle             = nil
    }
    
    // MARK: - Computed -

    private var isExceedingLimit: Bool {
        guard let value = AmountValidator().validate(enteredAmount), value > 0 else {
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
                        .foregroundStyle(.textMain)
                    }
                    
                    switch subtitle {
                    case .singleTransactionLimit:
                        if let limit = calculator.maxTransactionAmount {
                            Text("Enter up to \(limit.formatted())")
                                .fixedSize()
                                .foregroundStyle(subtitleColor)
                                .font(.appTextMedium)
                        }

                    case .balanceWithLimit(let maxBalance):
                        Text("Enter up to \(calculator.maxEnterAmount(maxBalance: maxBalance).formatted())")
                            .fixedSize()
                            .foregroundStyle(subtitleColor)
                            .font(.appTextMedium)

                    case .error(let text):
                        Text(text)
                            .fixedSize()
                            .foregroundStyle(.textError)
                            .font(.appTextMedium)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(currencySelectionAction == nil)
            .accessibilityIdentifier("amount-currency-button")
            
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
            
            if let actionOverride {
                actionOverride
                    .disabled(!actionEnabled(enteredAmount))
                    .padding(.top, 10)
            } else {
                CodeButton(
                    state: actionState,
                    style: mode.buttonStyle,
                    title: actionTitle ?? mode.actionName,
                    disabled: !actionEnabled(enteredAmount),
                    action: action
                )
                .padding(.top, 10)
            }
        }
    }
}

// MARK: - Mode -

extension EnterAmountView {
    enum Mode {

        case currency
        case withdraw
        case buy
        case sell
        case addMoney

        fileprivate func formatter(with currency: CurrencyCode) -> NumberFormatter {
            switch self {
            case .currency, .withdraw, .buy, .sell, .addMoney:
                return .fiat(currency: currency, minimumFractionDigits: 0)
            }
        }

        fileprivate var defaultValue: AmountField.DefaultValue {
            switch self {
            case .currency, .withdraw, .buy, .sell, .addMoney: return .number("0")
            }
        }

        fileprivate var actionName: String {
            switch self {
            case .currency: return "Next"
            case .withdraw: return "Next"
            case .buy:      return "Buy"
            case .sell:     return "Next"
            case .addMoney: return "Add Money"
            }
        }

        fileprivate var buttonStyle: CodeButton.Style {
            switch self {
            case .currency, .withdraw, .buy, .sell, .addMoney: return .filled
            }
        }
    }
}

// MARK: - Subtitle -

extension EnterAmountView {
    enum Subtitle {
        case singleTransactionLimit
        case balanceWithLimit(ExchangedFiat)
        /// Always rendered in `textError`. Use for soft-validation copy where
        /// Next stays enabled and the caller surfaces a dialog on tap.
        case error(String)
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
