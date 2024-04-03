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
    
    public let avatar: Image?
    public let username: String
    public let followerCount: Int?
    public let amount: String
    public let currency: CurrencyCode
    public let primaryAction: String
    public let secondaryAction: String
    public let paymentAction: ThrowingAction
    public let dismissAction: VoidAction
    public let cancelAction: VoidAction
    
    // MARK: - Init -
    

    public init(avatar: Image?, username: String, followerCount: Int?, amount: String, currency: CurrencyCode, primaryAction: String, secondaryAction: String, paymentAction: @escaping ThrowingAction, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.avatar = avatar
        self.username = username
        self.followerCount = followerCount
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
                    
                    if let avatar = avatar {
                        AvatarView(value: .image(avatar))
                    } else {
                        AvatarView(value: .placeholder)
                    }
                    
                    HStack {
                        Spacer()
                        Image.asset(.twitter)
                        Text(username)
                        Spacer()
                    }
                    .font(.appDisplaySmall)
                    
                    if let followerCount = followerCount {
                        Text("\(followerCount) Followers")
                            .font(.appTextSmall)
                            .foregroundColor(.textSecondary)
                    } else {
                        LoadingView(color: .textSecondary)
                    }
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
            avatar: nil,
            username: "ted_livingston",
            followerCount: 12_0000,
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
