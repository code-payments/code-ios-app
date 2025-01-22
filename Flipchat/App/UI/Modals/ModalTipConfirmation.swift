//
//  ModalTipConfirmation.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeUI
import FlipchatServices

public struct ModalTipConfirmation: View {
    
    @State private var selection: Int = 0
    
    public let amount: String
    public let balance: Kin
    public let currency: CurrencyCode
    public let primaryAction: String
    public let secondaryAction: String
    public let paymentAction: ThrowingAction
    public let dismissAction: VoidAction
    public let cancelAction: VoidAction
    
    // MARK: - Init -
    
    public init(amount: String, balance: Kin, currency: CurrencyCode, primaryAction: String, secondaryAction: String, paymentAction: @escaping ThrowingAction, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.amount = amount
        self.balance = balance
        self.currency = currency
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.paymentAction = paymentAction
        self.dismissAction = dismissAction
        self.cancelAction = cancelAction
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 20) {
            KinWheelView(
                selection: $selection,
                max: 100,
                width: 175
            )
            
            Text("Balance: \(balance.formattedTruncatedKin())")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            
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
            ModalTipConfirmation(
                amount: "200",
                balance: 1000,
                currency: .kin,
                primaryAction: "Swipe to Tip",
                secondaryAction: "Cancel",
                paymentAction: { try await Task.delay(seconds: 1) },
                dismissAction: {},
                cancelAction: {}
            )
        }
    }
}
