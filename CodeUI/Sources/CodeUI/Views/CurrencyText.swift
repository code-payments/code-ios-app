//
//  CurrencyText.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices

public struct CurrencyText: View {
    
    public let currency: CurrencyCode
    public let text: String
    
    // MARK: - Init -
    
    public init(currency: CurrencyCode, text: String) {
        self.currency = currency
        self.text = text
    }
    
    // MARK: - Body -
    
    public var body: some View {
        HStack(spacing: 10) {
            Flag(style: currency.flagStyle, size: .small)
                .layoutPriority(10)
            Text(text)
                .lineLimit(1)
                .layoutPriority(10)
        }
    }
}

// MARK: - Previews -

struct CurrencyText_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                CurrencyText(currency: .usd, text: "$5.00 of Kin")
                CurrencyText(currency: .cad, text: "$5.00 of Kin")
            }
        }
    }
}
