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
    private let actionEnabled: (String) -> Bool
    private let action: () -> Void
    private let currencySelectionAction: (() -> Void)?
    
    private var convertedEntryFiat: Fiat {
        session.exchangedEntryBalance.converted
    }
    
    // MARK: - Init -
    
    init(
        mode: Mode,
        enteredAmount: Binding<String>,
        actionState: Binding<ButtonState>,
        actionEnabled: @escaping (String) -> Bool,
        action: @escaping () -> Void,
        currencySelectionAction: (() -> Void)? = nil
    ) {
        self.mode                    = mode
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
                            prefix: .flagStyle(rateController.entryCurrency.flagStyle),
                            formatter: mode.formatter(with: rateController.entryCurrency),
                            suffix: nil,
                            showChevron: currencySelectionAction != nil
                        )
                        .foregroundColor(.textMain)
                    }
                    
                    Text("Enter up to \(convertedEntryFiat.formatted(suffix: nil))")
                        .fixedSize()
                        .foregroundColor(.textSecondary)
                        .font(.appTextMedium)
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
                style: .filled,
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
        
        case currency
        
        fileprivate func formatter(with currency: CurrencyCode) -> NumberFormatter {
            switch self {
            case .currency:
                return .fiat(currency: currency, minimumFractionDigits: 0)
            }
        }
        
        fileprivate var defaultValue: AmountField.DefaultValue {
            switch self {
            case .currency: return .number("0")
            }
        }
        
        fileprivate var actionName: String {
            switch self {
            case .currency:  return "Next"
            }
        }
    }
}

// MARK: - Previews -

#Preview {
    EnterAmountView(
        mode: .currency,
        enteredAmount: .constant("123"),
        actionState: .constant(.normal),
        actionEnabled: { _ in return true }
    ) {}
}
