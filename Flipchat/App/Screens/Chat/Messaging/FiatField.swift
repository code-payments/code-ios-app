//
//  FiatField.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI
import FlipchatServices

public struct FiatField: View {
    
    public let size: Size
    public let amount: KinAmount
    
    public init(size: Size, amount: KinAmount) {
        self.size = size
        self.amount = amount
    }
    
    public var body: some View {
        HStack(spacing: size.spacing) {
            Flag(style: amount.rate.currency.flagStyle, size: .none)
                .aspectRatio(contentMode: .fit)
                .frame(width: size.uiFont.lineHeight * 0.8)
            
            Text(amount.kin.formattedFiat(rate: amount.rate, showOfKin: true))
                .padding(.leading, 0)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .layoutPriority(10)
        }
        .font(size.font)
    }
    
    public enum Size {
        
        case small
        case large
        
        fileprivate var spacing: CGFloat {
            switch self {
            case .small:
                return 10
            case .large:
                return 12
            }
        }
        
        fileprivate var font: Font {
            switch self {
            case .small:
                return .appTextMedium
            case .large:
                return .appDisplaySmall
            }
        }
        
        fileprivate var uiFont: UIFont {
            switch self {
            case .small:
                return .appTextMedium
            case .large:
                return .appDisplaySmall
            }
        }
    }
}
