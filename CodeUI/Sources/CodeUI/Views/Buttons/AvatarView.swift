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
                PlaceholderAvatar()
            case .image(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(Circle())
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
    
    public var body: some View {
        VStack(spacing: 6) {
            
            UnevenRoundedCorners(
                tl: 20,
                bl: 15,
                br: 15,
                tr: 20
            )
            .fill(foregroundColor)
            .frame(width: 25, height: 28)
            .padding(.top, 20)
            
            Circle()
                .fill(foregroundColor)
                .frame(width: 50, height: 50)
        }
        .frame(width: 80, height: 80, alignment: .top)
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
