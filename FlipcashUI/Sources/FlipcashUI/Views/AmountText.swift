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
    private let flagSize: Flag.Size
    private let content: String
    private let showChevron: Bool
    private let canScale: Bool
    
    // MARK: - Init -
    
    public init(flagStyle: Flag.Style, flagSize: Flag.Size = .regular, content: String, showChevron: Bool = false, canScale: Bool = true) {
        self.flagStyle   = flagStyle
        self.flagSize    = flagSize
        self.content     = content
        self.showChevron = showChevron
        self.canScale    = canScale
    }
    
    public var body: some View {
        HStack(spacing: horizontalSpacing()) {
            HStack(spacing: 5) {
                Flag(
                    style: flagStyle,
                    size: flagSize
                )
                
                if showChevron {
                    Image.system(.chevronDown)
                        .font(.default(size: 12, weight: .bold))
                }
            }
            Text(content)
                .lineLimit(1)
                .minimumScaleFactor(canScale ? 0.3 : 1.0)
        }
    }
    
    private func horizontalSpacing() -> CGFloat {
        switch flagSize {
        case .small:
            return 8
        case .regular:
            return 15
        case .none:
            return 15
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
