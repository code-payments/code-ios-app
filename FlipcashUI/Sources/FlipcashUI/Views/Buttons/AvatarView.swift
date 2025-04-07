//
//  AvatarView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI
import FlipcashCore

//public struct AvatarView: View {
//    
//    @State private var value: Value
//    
//    private let diameter: CGFloat
//    
//    private var size: CGSize {
//        CGSize(width: diameter, height: diameter)
//    }
//    
//    private var isLoaded: Bool {
//        switch value {
//        case .placeholder, .url:
//            return false
//        case .image:
//            return true
//        }
//    }
//    
//    private var loadedImage: UIImage {
//        switch value {
//        case .placeholder, .url:
//            return UIImage()
//        case .image(let image):
//            return image
//        }
//    }
//    
//    // MARK: - Init -
//    
//    public init(value: Value, diameter: CGFloat = 80) {
//        self._value = State(wrappedValue: value)
//        self.diameter = diameter
//    }
//    
//    public var body: some View {
//        ZStack {
//            PlaceholderAvatar(diameter: diameter)
//                .opacity(isLoaded ? 0 : 1)
//            
//            Image(uiImage: loadedImage)
//                .resizable()
//                .aspectRatio(contentMode: .fit)
//                .mask(Circle())
//                .opacity(isLoaded ? 1 : 0)
//        }
//        .frame(width: diameter, height: diameter, alignment: .center)
//        .drawingGroup()
//        .onAppear {
//            if case .url(let imageURL) = value {
//                Task {
//                    let image = try await AvatarCache.shared.loadAvatar(url: imageURL)
//                    self.value = .image(image)
//                }
//            }
//        }
//    }
//}
//
//extension AvatarView {
//    public enum Value {
//        case placeholder
//        case image(UIImage)
//        case url(URL)
//    }
//}
//
//public struct PlaceholderAvatar: View {
//    
//    private let foregroundColor = Color(r: 97, g: 120, b: 136)
//    private let backgroundColor = Color(r: 201, g: 214, b: 222)
//    
//    private let diameter: CGFloat
//    
//    public init(diameter: CGFloat) {
//        self.diameter = diameter
//    }
//    
//    public var body: some View {
//        VStack(spacing: diameter * 0.075) {
//            
//            UnevenRoundedCorners(
//                tl: diameter * 0.25,
//                bl: diameter * 0.1875,
//                br: diameter * 0.1875,
//                tr: diameter * 0.25
//            )
//            .fill(foregroundColor)
//            .frame(width: diameter * 0.3125, height: diameter * 0.35)
//            .padding(.top, diameter * 0.25)
//            
//            Circle()
//                .fill(foregroundColor)
//                .frame(width: diameter * 0.625, height: diameter * 0.625)
//        }
//        .frame(width: diameter, height: diameter, alignment: .top)
//        .background(backgroundColor)
//        .mask {
//            Circle()
//        }
//        .drawingGroup()
//    }
//}
//
//// MARK: - Previews -
//
//struct AvatarView_Previews: PreviewProvider {
//    static var previews: some View {
//        VStack {
//            AvatarView(value: .placeholder)
//        }
//        .previewLayout(.fixed(width: 200.0, height: 200.0))
//    }
//}

#endif
