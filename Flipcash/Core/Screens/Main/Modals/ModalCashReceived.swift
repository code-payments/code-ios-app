//
//  ModalCashReceived.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

public struct ModalCashReceived: View {
    
    public let title: String
    public let fiat: Fiat
    public let actionTitle: String
    public let dismissAction: VoidAction
    
    // MARK: - Init -
    
    public init(title: String, fiat: Fiat, actionTitle: String, dismissAction: @escaping VoidAction) {
        self.title = title
        self.fiat = fiat
        self.actionTitle = actionTitle
        self.dismissAction = dismissAction
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.appTitle)
            
            AmountText(
                flagStyle: fiat.currencyCode.flagStyle,
                content: fiat.formatted(suffix: nil),
                canScale: false
            )
            .font(.appDisplayMedium)
            .foregroundStyle(Color.textMain)
            
            VStack {
                CodeButton(
                    style: .filled,
                    title: actionTitle,
                    action: dismissAction
                )
            }
            .padding(.top, 10)
        }
        .padding(20)
        .foregroundColor(.textMain)
        .font(.appTextMedium)
    }
}

#Preview {
    Background(color: .white) {
        ModalCashReceived(
            title: "Received",
            fiat: 5,
            actionTitle: "Cancel",
            dismissAction: {}
        )
    }
}
