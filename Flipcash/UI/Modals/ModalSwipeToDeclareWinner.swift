//
//  ModalSwipeToDeclareWinner.swift
//  Code
//
//  Created by Dima Bart on 2025-06-26.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

public struct ModalSwipeToDeclareWinner: View {
    
    public let outcome: PoolResoltion
    public let amount: Fiat
    public let swipeText: String
    public let cancelTitle: String
    public let paymentAction: ThrowingAction
    public let dismissAction: VoidAction
    public let cancelAction: VoidAction
    
    // MARK: - Init -
    
    public init(outcome: PoolResoltion, amount: Fiat, swipeText: String, cancelTitle: String, paymentAction: @escaping ThrowingAction, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.outcome       = outcome
        self.amount        = amount
        self.swipeText     = swipeText
        self.cancelTitle   = cancelTitle
        self.paymentAction = paymentAction
        self.dismissAction = dismissAction
        self.cancelAction  = cancelAction
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 10) {
            
            VStack(spacing: 10) {
                Text(outcome.text)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                Text("\(outcome.subtext) \(amount.formatted(suffix: nil))")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain.opacity(0.5))
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Metrics.boxRadius)
                    .fill(outcome.fillColor)
                    .strokeBorder(outcome.strokeColor, lineWidth: 1)
            }
            .padding(.top, 10)
            
            VStack {
                SwipeControl(
                    style: .green,
                    text: swipeText,
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
                    title: cancelTitle,
                    action: {
                        cancelAction()
                    }
                )
                .padding(.bottom, -20)
            }
            .padding(.top, 15)
        }
        .padding(20)
        .foregroundColor(.textMain)
        .font(.appTextMedium)
        .background(Color.backgroundMain)
    }
}

// MARK: - PoolResoltion -

extension PoolResoltion {
    
    var strokeColor: Color {
        switch self {
        case .yes, .no:
            Color(r: 77, g: 153, b: 97)
        case .refund:
            .lightStroke
        }
    }
    
    var fillColor: Color {
        switch self {
        case .yes, .no:
            .winnerGreen
        case .refund:
            .extraLightFill
        }
    }
    
    var text: String {
        switch self {
        case .yes:
            "Yes"
        case .no:
            "No"
        case .refund:
            "Tie"
        }
    }
    
    var subtext: String {
        switch self {
        case .yes:
            "Each winner receives"
        case .no:
            "Each winner receives"
        case .refund:
            "Everyone receives"
        }
    }
}
