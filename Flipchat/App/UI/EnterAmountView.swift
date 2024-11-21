//
//  WithdrawAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-04-05.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct EnterAmountView: View {
    
    @Binding var enteredAmount: String
    @Binding var actionState: ButtonState
    
    private let mode: Mode
    private let actionEnabled: (String) -> Bool
    private let action: () -> Void
    
    // MARK: - Init -
    
    init(
        mode: Mode,
        enteredAmount: Binding<String>,
        actionState: Binding<ButtonState>,
        actionEnabled: @escaping (String) -> Bool,
        action: @escaping () -> Void
    ) {
        self.mode           = mode
        self._enteredAmount = enteredAmount
        self._actionState   = actionState
        self.actionEnabled  = actionEnabled
        self.action         = action
    }
    
    // MARK: - Body -
    
    var body: some View {
        VStack(alignment: .center) {
            Spacer()
            
            Button {
                action()
            } label: {
                VStack(spacing: 5) {
                    HStack(spacing: 15) {
                        AmountField(
                            content: $enteredAmount,
                            defaultValue: mode.defaultValue,
                            prefix: mode.prefix,
                            formatter: mode.formatter,
                            suffix: nil,
                            showChevron: false
                        )
                        .foregroundColor(.textMain)
                    }
                    
//                    if let subtext {
//                        Text(subtext)
//                            .fixedSize()
//                            .foregroundColor(.textSecondary)
//                            .font(.appTextMedium)
//                    }
                }
                .frame(maxWidth: .infinity)
            }
            .contextMenu(ContextMenu {
                Button(action: copy) {
                    Label(Localized.Action.copy, systemImage: SystemSymbol.doc.rawValue)
                }
            })
            
            Spacer()
            
            KeyPadView(
                content: $enteredAmount,
                configuration: .number(),
                rules: KeyPadView.CurrencyRules(
                    maxIntegerDigits: 9,
                    maxDecimalDigits: 0
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
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = enteredAmount
    }
}

// MARK: - Mode -

extension EnterAmountView {
    enum Mode {
        
        case roomNumber
        case coverCharge
        
        fileprivate var formatter: NumberFormatter {
            switch self {
            case .roomNumber:  return .roomNumber
            case .coverCharge: return .fiat(
                currency: FlipchatServices.CurrencyCode.kin,
                minimumFractionDigits: 0,
                truncated: true
            )
            }
        }
        
        fileprivate var defaultValue: AmountField.DefaultValue {
            switch self {
            case .roomNumber:  return .string("#")
            case .coverCharge: return .string("0")
            }
        }
        
        fileprivate var prefix: AmountField.Prefix {
            switch self {
            case .roomNumber:  return .prefix("")
            case .coverCharge: return .flagStyle(.crypto(.kin))
            }
        }
        
        fileprivate var actionName: String {
            switch self {
            case .roomNumber:  return "Next"
            case .coverCharge: return "Save Changes"
            }
        }
    }
}

// MARK: - Currency Rules -

extension KeyPadView.CurrencyRules {

    static func code(hasDecimals: Bool) -> KeyPadView.CurrencyRules {
        KeyPadView.CurrencyRules(
            maxIntegerDigits: 9,
            maxDecimalDigits: hasDecimals ? 2 : 0
        )
    }
}

// MARK: - Previews -

#Preview {
    EnterAmountView(
        mode: .roomNumber,
        enteredAmount: .constant("123"),
        actionState: .constant(.normal),
        actionEnabled: { _ in return true }
    ) {}
}
