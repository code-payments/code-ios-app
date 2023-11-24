//
//  AmountText.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices

public struct AmountText: View {
    
    private let flagStyle: Flag.Style
    private let content: String
    
    // MARK: - Init -
    
    public init(flagStyle: Flag.Style, content: String) {
        self.flagStyle = flagStyle
        self.content  = content
    }
    
    public var body: some View {
        HStack(spacing: 15) {
            Flag(style: flagStyle)
            Text(content)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
        }
    }
}

// MARK: - Previews -

struct AmountText_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AmountText(flagStyle: .fiat(.ca), content: "$13.50")
            AmountText(flagStyle: .fiat(.us), content: "$1,385.50")
            AmountText(flagStyle: .fiat(.jp), content: "$13,930,173.50")
        }
        .previewLayout(.fixed(width: 480, height: 100))
    }
}
