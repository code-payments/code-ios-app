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
    
    public let username: String
    public let amount: String
    public let currency: CurrencyCode
    public let avatar: Image?
    public let user: TwitterUser?
    public let primaryAction: String
    public let secondaryAction: String
    public let paymentAction: ThrowingAction
    public let dismissAction: VoidAction
    public let cancelAction: VoidAction
    
    // MARK: - Init -
    

    public init(username: String, amount: String, currency: CurrencyCode, avatar: Image?, user: TwitterUser?, primaryAction: String, secondaryAction: String, paymentAction: @escaping ThrowingAction, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.username = username
        self.amount = amount
        self.currency = currency
        self.avatar = avatar
        self.user = user
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
                        if let verificationAsset = user?.verificationStatus.asset {
                            Image.asset(verificationAsset)
                                .padding(.top, 4)
                        }
                        Spacer()
                    }
                    .font(.appDisplaySmall)
                    
                    if let followerCount = user?.followerCount {
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

extension TwitterUser.VerificationStatus {
    var asset: Asset? {
        switch self {
        case .blue:
            return .twitterBlue
        case .business:
            return .twitterGrey
        case .government:
            return .twitterGold
        case .none, .unknown:
            return nil
        }
    }
}

#Preview {
    Background(color: .white) {
        ModalTipConfirmation(
            username: "ted_livingston",
            amount: "$5.00 of Kin",
            currency: .cad,
            avatar: nil,
            user: TwitterUser(
                username: "ted_livingston",
                displayName: "Ted Livingston",
                avatarURL: URL(string: "")!,
                followerCount: 12_000,
                tipAddress: .mock,
                verificationStatus: .blue
            ),
            primaryAction: "Swipe to Tip",
            secondaryAction: "Cancel",
            paymentAction: {},
            dismissAction: {},
            cancelAction: {}
        )
    }
}
