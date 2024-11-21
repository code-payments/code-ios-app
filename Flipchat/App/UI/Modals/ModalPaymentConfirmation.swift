//
//  ModalPaymentConfirmation.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeUI
import FlipchatServices

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
        VStack(spacing: 10) {
            
            AmountText(
                flagStyle: currency.flagStyle,
                content: amount
            )
            .font(.appDisplayMedium)
            .padding(.top, 20)
            
            VStack {
                SwipeControl(
                    style: .purple,
                    text: primaryAction,
                    action: {
                        try await paymentAction()
                        try await Task.delay(milliseconds: 500)
                    },
                    completion: {
                        dismissAction()
                        try await Task.delay(milliseconds: 1000) // Checkmark delay
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
            .padding(.top, 25)
        }
        .padding(20)
        .foregroundColor(.textMain)
        .font(.appTextMedium)
        .background(Color.backgroundMain)
    }
}

#Preview {
    Background(color: .backgroundMain) {}
    .sheet(isPresented: .constant(true)) {
        PartialSheet {
            ModalPaymentConfirmation(
                amount: "200",
                currency: .kin,
                primaryAction: "Swipe to Pay",
                secondaryAction: "Cancel",
                paymentAction: { try await Task.delay(seconds: 1) },
                dismissAction: {},
                cancelAction: {}
            )
        }
    }
}
