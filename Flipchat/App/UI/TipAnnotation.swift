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
            .frame(height: 27)
            .padding(.horizontal, 10)
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

struct ReactionAnnotation: View {
    
    private let emoji: String
    private let count: Int
    private let isFilled: Bool
    private let action: () -> Void
    
    init(emoji: String, count: Int, isFilled: Bool, action: @escaping () -> Void) {
        self.emoji = emoji
        self.count = count
        self.isFilled = isFilled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(emoji)
                    .font(.appTextSmall)
                    .padding(.bottom, 3)
                    .fixedSize(horizontal: true, vertical: false)
                
                Text("\(count)")
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.appTextHeading)
            }
            .frame(height: 27)
            .padding(.horizontal, 10)
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
