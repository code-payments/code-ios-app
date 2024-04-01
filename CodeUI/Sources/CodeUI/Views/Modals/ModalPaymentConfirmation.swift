//
//  ModalPaymentConfirmation.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices

/// Modal to confirm and execute a payment request card
public struct ModalPaymentConfirmation: View {
    
    public let amount: String
    public let currency: CurrencyCode
    public let primaryAction: String
    public let secondaryAction: String
    public let paymentAction: ThrowingAction
    public let dismissAction: VoidAction
    public let cancelAction: VoidAction
    
    // MARK: - Init -
    
    public init(amount: String, currency: CurrencyCode, primaryAction: String, secondaryAction: String, paymentAction: @escaping ThrowingAction, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.amount = amount
        self.currency = currency
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.paymentAction = paymentAction
        self.dismissAction = dismissAction
        self.cancelAction = cancelAction
    }
    
    // MARK: - Body -
    
    public var body: some View {
        SheetView(edge: .bottom, backgroundColor: .backgroundMain) {
            VStack(spacing: 10) {
                
                AmountText(
                    flagStyle: currency.flagStyle,
                    content: amount
                )
                .font(.appDisplayMedium)
                
                VStack {
                    SwipeControl(
                        style: .blue,
                        text: primaryAction,
                        action: {
                            try await paymentAction()
                        },
                        completion: {
                            try await Task.delay(seconds: 1) // Checkmark delay
                            dismissAction()
                        }
                    )
                    
                    CodeButton(
                        style: .subtle,
                        title: secondaryAction,
                        action: {
                            cancelAction()
                        }
                    )
                    .padding(.bottom, -20)
                }
                .padding(.top, 10)
            }
            .padding(20)
            .padding(.top, 5)
            .foregroundColor(.textMain)
            .font(.appTextMedium)
        }
    }
}
