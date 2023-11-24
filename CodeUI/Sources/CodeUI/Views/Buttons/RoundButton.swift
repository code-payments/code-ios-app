//
//  RoundButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct RoundButton: View {
    
    private let image: Image
    private let size: CGSize
    private let action: VoidAction
    
    // MARK: - Init -
    
    public init(_ systemSymbol: SystemSymbol, size: Size, binding: Binding<Bool>) {
        self.init(image: Image.system(systemSymbol), size: size, binding: binding)
    }
    
    public init(_ systemSymbol: SystemSymbol, size: Size, action: @escaping VoidAction) {
        self.init(image: Image.system(systemSymbol), size: size, action: action)
    }
    
    public init(asset: Asset, size: Size, binding: Binding<Bool>) {
        self.init(image: Image.asset(asset), size: size, binding: binding)
    }
    
    public init(asset: Asset, size: Size, action: @escaping VoidAction) {
        self.init(image: Image.asset(asset), size: size, action: action)
    }
    
    public init(image: Image, size: Size, binding: Binding<Bool>) {
        self.init(image: image, size: size) {
            binding.wrappedValue.toggle()
        }
    }
    
    public init(image: Image, size: Size, action: @escaping VoidAction) {
        self.image  = image
        self.size   = size.cgSize
        self.action = action
    }
    
    // MARK: - Body -
    
    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.textMain.opacity(0.07))
                    .background(
                        Circle()
                            .strokeBorder(Color.textMain.opacity(0.1), lineWidth: 1)
                    )
                image
                    .foregroundColor(Color.textMain)
                    .font(.appTextLarge)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

// MARK: - Size -

extension RoundButton {
    public enum Size {
        
        case regular
        case large
        
        fileprivate var cgSize: CGSize {
            switch self {
            case .regular:
                return CGSize(width: 44, height: 44)
            case .large:
                return CGSize(width: 60, height: 60)
            }
        }
    }
}

// MARK: - Previews -

struct RoundButton_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                Spacer()
                RoundButton(.info,      size: .regular, action: {})
                RoundButton(.arrowUp,   size: .regular, action: {})
                RoundButton(.arrowDown, size: .regular, action: {})
                RoundButton(.info,      size: .large, action: {})
                RoundButton(.arrowUp,   size: .large, action: {})
                RoundButton(.arrowDown, size: .large, action: {})
                Spacer()
            }
            .padding(20.0)
        }
        .previewLayout(.fixed(width: 300, height: 400))
    }
}
