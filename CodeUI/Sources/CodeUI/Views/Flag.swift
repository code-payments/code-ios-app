//
//  Flag.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices

public struct Flag: View {

    public let style: Style
    public let size: Size
    
    public init(style: Style, size: Size = .regular) {
        self.style = style
        self.size = size
    }
    
    public var body: some View {
        switch style {
        case .fiat(let region):
            Image.regionFlag(region)
                .resizable()
                .if(size != .none) { $0
                    .frame(width: size.dimensions.width, height: size.dimensions.height)
                }
                .mask { Circle() }
            
        case .crypto(let currency):
            Image.cryptoFlag(currency)
                .resizable()
                .if(size != .none) { $0
                    .frame(width: size.dimensions.width, height: size.dimensions.height)
                }
                .mask { Circle() }
        }
    }
}

extension Flag {
    public enum Style {
        
        case fiat(Region)
        case crypto(CurrencyCode)
        
        public static func from(region: Region?, currency: CurrencyCode) -> Style {
            if let region = region {
                return .fiat(region)
            } else {
                return .crypto(currency)
            }
        }
    }
}

extension Flag {
    public enum Size {
        
        case small
        case regular
        case none
        
        var dimensions: CGSize {
            switch self {
            case .small:
                return CGSize(width: 15, height: 15)
                
            case .regular:
                return CGSize(width: 30, height: 30)
                
            case .none:
                return .zero
            }
        }
    }
}

// MARK: - Currency -

extension CurrencyCode {
    public var flagStyle: Flag.Style {
        if let region = region {
            return .fiat(region)
        } else {
            return .crypto(self)
        }
    }
}
