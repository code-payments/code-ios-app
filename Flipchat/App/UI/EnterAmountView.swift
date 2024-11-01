//
//  WithdrawAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-04-05.
//

import SwiftUI
import CodeUI
import CodeServices

struct EnterAmountView: View {
    
    @Binding var enteredAmount: String
    @Binding var actionState: ButtonState
    
    private let subtext: String?
    private let formatter: NumberFormatter
    private let suffix: String?
    private let actionEnabled: (String) -> Bool
    private let action: () -> Void
    
    // MARK: - Init -
    
    init(enteredAmount: Binding<String>, actionState: Binding<ButtonState>, subtext: String?, formatter: NumberFormatter, suffix: String? = nil, actionEnabled: @escaping (String) -> Bool, action: @escaping () -> Void) {
        self._enteredAmount = enteredAmount
        self._actionState   = actionState
        self.subtext        = subtext
        self.formatter      = formatter
        self.suffix         = suffix
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
                            defaultValue: .string("#"),
                            prefix: "",
                            formatter: formatter,
                            suffix: suffix
                        )
                        .foregroundColor(.textMain)
                    }
                    
                    if let subtext {
                        Text(subtext)
                            .fixedSize()
                            .foregroundColor(.textSecondary)
                            .font(.appTextMedium)
                    }
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
                title: Localized.Action.next,
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
        enteredAmount: .constant("123"),
        actionState: .constant(.normal),
        subtext: "Enter Room Number",
        formatter: .roomNumber,
        suffix: "Kin",
        actionEnabled: { _ in return true }
    ) {}
}
