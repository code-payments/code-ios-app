//
//  ModalInsufficientFunds.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices
import CodeUI

/// Modal to confirm and execute a payment request card
public struct ModalInsufficientFunds: View {
    
    public let title: String
    public let subtitle: String
    public let primaryAction: String
    public let secondaryAction: String
    public let getMoreKinAction: VoidAction
    public let dismissAction: VoidAction
    
    // MARK: - Init -
    
    public init(title: String, subtitle: String, primaryAction: String, secondaryAction: String, getMoreKinAction: @escaping VoidAction, dismissAction: @escaping VoidAction) {
        self.title = title
        self.subtitle = subtitle
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.getMoreKinAction = getMoreKinAction
        self.dismissAction = dismissAction
    }
    
    // MARK: - Body -
    
    public var body: some View {
        SheetView(edge: .bottom, backgroundColor: .backgroundMain) {
            VStack(spacing: 10) {
                
                VStack(spacing: 10) {
                    Text(title)
                        .font(.appDisplaySmall)
                    
                    Text(subtitle)
                        .font(.appTextSmall)
                }
                .multilineTextAlignment(.center)
                
                VStack {
                    CodeButton(
                        style: .filled,
                        title: primaryAction,
                        action: {
                            getMoreKinAction()
                        }
                    )
                    
                    CodeButton(
                        style: .subtle,
                        title: secondaryAction,
                        action: {
                            dismissAction()
                        }
                    )
                    .padding(.bottom, -20)
                }
                .padding(.top, 15)
            }
            .padding(20)
            .padding(.top, 5)
            .foregroundColor(.textMain)
            .font(.appTextMedium)
        }
    }
}

#Preview {
    Background(color: .white) {
        ModalInsufficientFunds(
            title: "Insufficient Funds",
            subtitle: "Please get more Kin and then try paying again.",
            primaryAction: "Get More Kin",
            secondaryAction: "Cancel",
            getMoreKinAction: {},
            dismissAction: {}
        )
    }
}
