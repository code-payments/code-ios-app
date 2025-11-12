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
    public let fiat: Quarks
    public let currencyName: String
    public let currencyImageURL: URL?
    public let actionTitle: String
    public let dismissAction: VoidAction
    
    // MARK: - Init -
    
    public init(title: String, fiat: Quarks, currencyName: String, currencyImageURL: URL?, actionTitle: String, dismissAction: @escaping VoidAction) {
        self.title = title
        self.fiat = fiat
        self.currencyName = currencyName
        self.currencyImageURL = currencyImageURL
        self.actionTitle = actionTitle
        self.dismissAction = dismissAction
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.appTitle)
            
            VStack(spacing: 6) {
                AmountText(
                    flagStyle: fiat.currencyCode.flagStyle,
                    content: fiat.formatted(),
                    canScale: false
                )
                .font(.appDisplayMedium)
                .foregroundStyle(Color.textMain)
                
                HStack(spacing: 2) {
                    Text("of ")
                    
                    RemoteImage(url: currencyImageURL)
                        .frame(width: 15, height: 15)
                        .clipShape(Circle())
                    
                    Text(currencyName)
                }
                .font(.appBarButton)
                .foregroundStyle(Color.textSecondary)
            }
            
            CodeButton(
                style: .filled,
                title: actionTitle,
                action: dismissAction
            )
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
            currencyName: "Jeffy",
            currencyImageURL: nil,
            actionTitle: "Cancel",
            dismissAction: {}
        )
    }
}
