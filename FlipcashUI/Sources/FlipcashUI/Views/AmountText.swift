//
//  AmountText.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

public struct AmountText: View {
    
    private let flagStyle: Flag.Style
    private let content: String
    public let showChevron: Bool
    
    // MARK: - Init -
    
    public init(flagStyle: Flag.Style, content: String, showChevron: Bool = false) {
        self.flagStyle = flagStyle
        self.content  = content
        self.showChevron = showChevron
    }
    
    public var body: some View {
        HStack(spacing: 15) {
            HStack(spacing: 5) {
                Flag(style: flagStyle)
                if showChevron {
                    Image.system(.chevronDown)
                        .font(.default(size: 12, weight: .bold))
                }
            }
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
