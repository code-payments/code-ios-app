//
//  ModalCashReceived.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices
import CodeUI

/// Modal that displays received amount of Kin at local fiat rates
public struct ModalCashReceived: View {
    
    public let title: String
    public let amount: String
    public let currency: CurrencyCode
    public let secondaryAction: String
    public let dismissAction: VoidAction
    
    // MARK: - Init -
    
    public init(title: String, amount: String, currency: CurrencyCode, secondaryAction: String, dismissAction: @escaping VoidAction) {
        self.title = title
        self.amount = amount
        self.currency = currency
        self.secondaryAction = secondaryAction
        self.dismissAction = dismissAction
    }
    
    // MARK: - Body -
    
    public var body: some View {
        SheetView(edge: .bottom, backgroundColor: .backgroundMain) {
            VStack(spacing: 10) {
                Text(title)
                    .font(.appTitle)
                
                AmountText(
                    flagStyle: currency.flagStyle,
                    content: amount
                )
                .font(.appDisplayMedium)
                
                VStack {
                    CodeButton(
                        style: .filled,
                        title: secondaryAction,
                        action: dismissAction
                    )
                }
                .padding(.top, 10)
            }
            .padding(20)
            .foregroundColor(.textMain)
            .font(.appTextMedium)
        }
    }
}

#Preview {
    Background(color: .white) {
        ModalCashReceived(
            title: "Received",
            amount: "$5.00",
            currency: .cad,
            secondaryAction: "Cancel",
            dismissAction: {}
        )
    }
}
