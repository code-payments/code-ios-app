//
//  TipAnnotation.swift
//  Code
//
//  Created by Dima Bart on 2025-01-22.
//

import SwiftUI
import FlipchatServices
import CodeUI

struct TipAnnotation: View {
    
    private let kin: Kin
    private let isFilled: Bool
    private let action: () -> Void
    
    init(kin: Kin, isFilled: Bool, action: @escaping () -> Void) {
        self.kin = kin
        self.isFilled = isFilled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(String.unicodeHex)
                    .font(.appTextLarge)
                    .padding(.bottom, 3)
                    .fixedSize(horizontal: true, vertical: false)
                
                Text(kin.formattedTruncatedKin(showSymbol: false, showSuffix: false))
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.appTextHeading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 0)
            .background {
                if isFilled {
                    RoundedRectangle(cornerRadius: 99)
                        .fill(Color.actionSecondary)
                } else {
                    RoundedRectangle(cornerRadius: 99)
                        .strokeBorder(Color.actionSecondary, lineWidth: 1)
                }
            }
        }
    }
}
