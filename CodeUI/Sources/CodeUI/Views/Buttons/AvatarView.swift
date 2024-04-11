//
//  AvatarView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct AvatarView: View {
    
    public let value: Value
    
    private let size = CGSize(width: 80, height: 80)
    
    // MARK: - Init -
    
    public init(value: Value) {
        self.value = value
    }
    
    public var body: some View {
//        AsyncImage(url: url) { phase in
//            if let image = phase.image {
//                image
//                    .resizable()
//                    .aspectRatio(contentMode: .fit)
//                    .clipShape(Circle())
//                    .drawingGroup()
//            } else {
//                PlaceholderAvatar()
//            }
//        }
        Group {
            switch value {
            case .placeholder:
                PlaceholderAvatar(diameter: 80)
            case .image(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(max(size.width, size.height))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
    }
}

extension AvatarView {
    public enum Value {
        case placeholder
        case image(Image)
    }
}

public struct PlaceholderAvatar: View {
    
    private let foregroundColor = Color(r: 97, g: 120, b: 136)
    private let backgroundColor = Color(r: 201, g: 214, b: 222)
    
    private let diameter: CGFloat
    
    public init(diameter: CGFloat) {
        self.diameter = diameter
    }
    
    public var body: some View {
        VStack(spacing: diameter * 0.075) {
            
            UnevenRoundedCorners(
                tl: diameter * 0.25,
                bl: diameter * 0.1875,
                br: diameter * 0.1875,
                tr: diameter * 0.25
            )
            .fill(foregroundColor)
            .frame(width: diameter * 0.3125, height: diameter * 0.35)
            .padding(.top, diameter * 0.25)
            
            Circle()
                .fill(foregroundColor)
                .frame(width: diameter * 0.625, height: diameter * 0.625)
        }
        .frame(width: diameter, height: diameter, alignment: .top)
        .background(backgroundColor)
        .mask {
            Circle()
        }
        .drawingGroup()
    }
}

// MARK: - Previews -

struct AvatarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            AvatarView(value: .placeholder)
        }
        .previewLayout(.fixed(width: 200.0, height: 200.0))
    }
}

#endif
