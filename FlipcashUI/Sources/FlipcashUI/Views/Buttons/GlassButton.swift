//
//  GlassButton.swift
//  FlipcashUI
//
//  Created by Claude Code.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct GlassButton: View {

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
            image
                .foregroundStyle(Color.textMain)
                .font(.appTextLarge)
                .frame(width: size.width, height: size.height)
        }
        .buttonStyle(.liquidGlassCompatibleCircle)
    }
}

// MARK: - Size -

extension GlassButton {
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

struct GlassButton_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                Spacer()
                GlassButton(.info,      size: .regular, action: {})
                GlassButton(.arrowUp,   size: .regular, action: {})
                GlassButton(.arrowDown, size: .regular, action: {})
                GlassButton(asset: .hamburger, size: .regular, action: {})
                GlassButton(.info,      size: .large, action: {})
                GlassButton(.arrowUp,   size: .large, action: {})
                GlassButton(.arrowDown, size: .large, action: {})
                GlassButton(asset: .hamburger, size: .large, action: {})
                Spacer()
            }
            .padding(20.0)
        }
        .previewLayout(.fixed(width: 300, height: 600))
    }
}
