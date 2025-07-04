//
//  ModalSwipeToBet.swift
//  Code
//
//  Created by Dima Bart on 2025-06-26.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

public struct ModalSwipeToBet: View {
    
    public let fiat: Fiat
    public let subtext: String
    public let swipeText: String
    public let cancelTitle: String
    public let paymentAction: ThrowingAction
    public let dismissAction: VoidAction
    public let cancelAction: VoidAction
    
    // MARK: - Init -
    
    public init(fiat: Fiat, subtext: String, swipeText: String, cancelTitle: String, paymentAction: @escaping ThrowingAction, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.fiat = fiat
        self.subtext = subtext
        self.swipeText = swipeText
        self.cancelTitle = cancelTitle
        self.paymentAction = paymentAction
        self.dismissAction = dismissAction
        self.cancelAction = cancelAction
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 10) {
            
            VStack(spacing: 10) {
                AmountText(
                    flagStyle: fiat.currencyCode.flagStyle,
                    content: fiat.formatted(suffix: nil)
                )
                .font(.appDisplayMedium)
                .foregroundStyle(Color.textMain)
                .padding(.top, 20)
                
                Text(subtext)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
            }
            
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
            .padding(.top, 25)
        }
        .padding(20)
        .foregroundColor(.textMain)
        .font(.appTextMedium)
        .background(Color.backgroundMain)
    }
}
