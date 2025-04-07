//
//  CodeBrand.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct CodeBrand: View {
    
    public var size: Size
    public var isTemplate: Bool
    
    public init(size: Size, template: Bool = false) {
        self.size = size
        self.isTemplate = template
    }
    
    public var body: some View {
        Image.asset(.codeBrand)
            .resizable()
            .renderingMode(isTemplate ? .template : .original)
            .aspectRatio(contentMode: .fit)
            .if(size != .flexible) { $0
                .frame(width: size.width)
            }
    }
}

extension CodeBrand {
    public enum Size {
        
        case flexible
        case small
        case medium
        case large
        
        var width: CGFloat {
            switch self {
            case .flexible: return 0
            case .small:    return 100
            case .medium:   return 150
            case .large:    return 230
            }
        }
    }
}

// MARK: - Previews -

struct CodeLogo_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 30) {
                CodeBrand(size: .large)
                CodeBrand(size: .medium)
                CodeBrand(size: .small)
            }
        }
        .previewLayout(.fixed(width: 320, height: 500))
    }
}
