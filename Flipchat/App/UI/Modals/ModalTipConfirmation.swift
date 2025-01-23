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
    
    @State private var selection: Int = 1
    
    public let balance: Kin
    public let primaryAction: String
    public let secondaryAction: String
    public let paymentAction: (Kin) async throws -> Void
    public let dismissAction: VoidAction
    public let cancelAction: VoidAction
    
    // MARK: - Init -
    
    public init(balance: Kin, primaryAction: String, secondaryAction: String, paymentAction: @escaping (Kin) async throws -> Void, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.balance = balance
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
                max: 99,
                width: 155
            )
            
            Text("Balance: \(balance.formattedTruncatedKin())")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            
            VStack {
                SwipeControl(
                    style: .purple,
                    text: primaryAction,
                    action: {
                        try await paymentAction(Kin(kin: selection)!)
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
                balance: 1000,
                primaryAction: "Swipe to Tip",
                secondaryAction: "Cancel",
                paymentAction: { _ in try await Task.delay(seconds: 1) },
                dismissAction: {},
                cancelAction: {}
            )
        }
    }
}
