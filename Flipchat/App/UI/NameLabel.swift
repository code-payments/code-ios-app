//
//  MemberNameLabel.swift
//  Code
//
//  Created by Dima Bart on 2025-03-03.
//

import SwiftUI
import CodeUI

struct MemberNameLabel: View {
    
    let size: Size
    let showLogo: Bool
    let name: String
    let verificationType: VerificationType
    
    init(size: Size, showLogo: Bool, name: String, verificationType: VerificationType) {
        self.size = size
        self.showLogo = showLogo
        self.name = name
        self.verificationType = verificationType
    }
    
    var body: some View {
        HStack(spacing: size.horizontalSpacing()) {
            if showLogo {
                let d = size.logoSize()
                Image.asset(.twitter)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: d, height: d)
            }
            
            Text(name)
                .font(size.font())
                .minimumScaleFactor(0.9)
                .lineLimit(1)
            
            if let image = Image.verificationBadge(for: verificationType) {
                let d = size.verificationSize()
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: d, height: d)
                    .padding(.leading, 2) // Offset to center the displayName against the X logo
            }
        }
        .foregroundStyle(Color.textMain)
    }
}

// MARK: - Size -

extension MemberNameLabel {
    enum Size {
        case small
        case medium
        case large
        
        fileprivate func horizontalSpacing() -> CGFloat {
            switch self {
            case .small:   return 2
            case .medium:  return 4
            case .large:   return 6
            }
        }
        
        fileprivate func logoSize() -> CGFloat {
            switch self {
            case .small:   return 18
            case .medium:  return 10
            case .large:   return 22
            }
        }
        
        fileprivate func font() -> Font {
            switch self {
            case .small:   return .appTextCaption
            case .medium:  return .appTextMedium
            case .large:   return .appTextLarge
            }
        }
        
        fileprivate func verificationSize() -> CGFloat {
            switch self {
            case .small:   return 14
            case .medium:  return 16
            case .large:   return 20
            }
        }
    }
}
