//
//  BlurButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct BlurButton: View {
    
    private let image: Image
    private let style: UIBlurEffect.Style
    private let action: VoidAction
    
    // MARK: - Init -
    
    public init(_ systemSymbol: SystemSymbol, style: UIBlurEffect.Style = .systemUltraThinMaterial, action: @escaping VoidAction) {
        self.init(image: Image.system(systemSymbol), style: style, action: action)
    }
    
    public init(_ asset: Asset, style: UIBlurEffect.Style = .systemUltraThinMaterial, action: @escaping VoidAction) {
        self.init(image: Image.asset(asset), style: style, action: action)
    }
    
    public init(image: Image, style: UIBlurEffect.Style = .systemUltraThinMaterial, binding: Binding<Bool>) {
        self.init(image: image, style: style) {
            binding.wrappedValue.toggle()
        }
    }
    
    public init(image: Image, style: UIBlurEffect.Style = .systemUltraThinMaterial, action: @escaping VoidAction) {
        self.image  = image
        self.style  = style
        self.action = action
    }
    
    // MARK: - Body -
    
    public var body: some View {
        BlurView(style: style) {
            Button(action: action) {
                image
                    .foregroundColor(Color.textMain)
                    .font(.appTextLarge)
                    .frame(width: 60, height: 60)
            }
        }
        .clipShape(Circle())
    }
}

// MARK: - Previews -

struct BlurButton_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                Spacer()
                BlurButton(.close,      action: {})
                BlurButton(.arrowUp,   action: {})
                BlurButton(.arrowDown, action: {})
                Spacer()
            }
            .padding(20.0)
        }
        .previewLayout(.fixed(width: 300, height: 400))
    }
}

#endif
