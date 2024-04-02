//
//  ModalTipConfirmation.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices
import CodeUI
import CodeUI

/// Modal to confirm and execute a tip request card
public struct ModalTipConfirmation: View {
    
    public let avatarURL: URL?
    public let username: String
    public let subtitle: String
    public let amount: String
    public let currency: CurrencyCode
    public let primaryAction: String
    public let secondaryAction: String
    public let paymentAction: ThrowingAction
    public let dismissAction: VoidAction
    public let cancelAction: VoidAction
    
    // MARK: - Init -
    

    public init(avatarURL: URL?, username: String, subtitle: String, amount: String, currency: CurrencyCode, primaryAction: String, secondaryAction: String, paymentAction: @escaping ThrowingAction, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.avatarURL = avatarURL
        self.username = username
        self.subtitle = subtitle
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
            VStack(spacing: 0) {
                
                VStack(alignment: .center) {
                    
                    AvatarView(url: avatarURL, action: nil)
                        .disabled(true)
                    
                    HStack {
                        Spacer()
                        Image.asset(.twitter)
                        Text(username)
                        Spacer()
                    }
                    .font(.appDisplaySmall)
                    
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundColor(.textSecondary)
                }
                .padding(.bottom, 40)
                .vSeparator(color: .textSecondary)
                .padding(.bottom, 20)
                .padding(.top, 30)
                
                AmountText(
                    flagStyle: currency.flagStyle,
                    content: amount
                )
                .font(.appDisplayMedium)
                .padding([.top, .bottom], 10)
                
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
            .foregroundColor(.textMain)
            .font(.appTextMedium)
        }
    }
}

#Preview {
    Background(color: .white) {
        ModalTipConfirmation(
            avatarURL: nil,
            username: "ted_livingston",
            subtitle: "12k Followers",
            amount: "$5.00 of Kin",
            currency: .cad,
            primaryAction: "Swipe to Tip",
            secondaryAction: "Cancel",
            paymentAction: {},
            dismissAction: {},
            cancelAction: {}
        )
    }
}
