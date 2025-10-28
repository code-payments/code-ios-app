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
    
    @EnvironmentObject var session: Session
    @EnvironmentObject var rateController: RatesController
    
    @Binding public var enteredAmount: String
    @Binding public var actionState: ButtonState
    
    private let mode: Mode
    private let subtitle: Subtitle
    private let actionEnabled: (String) -> Bool
    private let action: () -> Void
    private let currencySelectionAction: (() -> Void)?
    
    private var maxTransactionAmount: Fiat {
        guard let limit = session.singleTransactionLimitFor(currency: currency) else {
            return 0
        }
        
        return limit
    }
    
    private var currency: CurrencyCode {
        switch mode {
        case .currency:
            rateController.entryCurrency
        case .onramp:
            rateController.onrampCurrency
        case .walletDeposit, .phantomDeposit, .withdraw:
            .usd
        }
    }
    
    func maxEnterAmount(maxBalance: Fiat) -> Fiat {
        guard let limit = session.nextTransactionLimit(currency: currency) else {
            return 0
        }
        
        let (max, lim, _) = try! maxBalance.aligned(with: limit)
        
        guard max.quarks <= lim.quarks else {
            return limit
        }
        
        return maxBalance
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
                            prefix: .flagStyle(currency.flagStyle),
                            formatter: mode.formatter(with: currency),
                            suffix: nil,
                            showChevron: currencySelectionAction != nil
                        )
                        .foregroundColor(.textMain)
                    }
                    
                    switch subtitle {
                    case .singleTransactionLimit:
                        Text("Enter up to \(maxTransactionAmount.formatted(suffix: nil))")
                            .fixedSize()
                            .foregroundColor(.textSecondary)
                            .font(.appTextMedium)
                        
                    case .balanceWithLimit(let maxBalance):
                        Text("Enter up to \(maxEnterAmount(maxBalance: maxBalance).formatted(suffix: nil))")
                            .fixedSize()
                            .foregroundColor(.textSecondary)
                            .font(.appTextMedium)
                        
                    case .custom(let text):
                        Text(text)
                            .fixedSize()
                            .foregroundColor(.textSecondary)
                            .font(.appTextMedium)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(currencySelectionAction == nil)
            
            Spacer()
            
            KeyPadView(
                content: $enteredAmount,
                configuration: .decimal(),
                rules: KeyPadView.CurrencyRules(
                    maxIntegerDigits: 9,
                    maxDecimalDigits: 2
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
        
        fileprivate func formatter(with currency: CurrencyCode) -> NumberFormatter {
            switch self {
            case .currency, .onramp, .walletDeposit, .phantomDeposit, .withdraw:
                return .fiat(currency: currency, minimumFractionDigits: 0)
            }
        }
        
        fileprivate var defaultValue: AmountField.DefaultValue {
            switch self {
            case .phantomDeposit: return .number("0")
            case .walletDeposit:  return .number("0")
            case .currency:       return .number("0")
            case .onramp:         return .number("0")
            case .withdraw:       return .number("0")
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
            }
        }
        
        fileprivate var buttonStyle: CodeButton.Style {
            switch self {
            case .phantomDeposit: return .filledCustom(Image.asset(.phantom), "Phantom")
            case .walletDeposit:  return .filled
            case .currency:       return .filled
            case .onramp:         return .filledApplePay
            case .withdraw:       return .filled
            }
        }
    }
}

// MARK: - Subtitle -

extension EnterAmountView {
    enum Subtitle {
        case singleTransactionLimit
        case balanceWithLimit(Fiat)
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
