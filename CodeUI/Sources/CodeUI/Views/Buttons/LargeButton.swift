//
//  LargeButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct LargeButton<Content>: View where Content: View {
    
    private let title: String?
    private let content: () -> Content
    private let spacing: CGFloat
    private let maxWidth: CGFloat?
    private let maxHeight: CGFloat?
    private let fullWidth: Bool
    private let aligment: Alignment
    private let action: VoidAction
    
    public init(title: String?, content: @escaping () -> Content, spacing: CGFloat = 0, maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil, fullWidth: Bool = false, aligment: Alignment = .center, binding: Binding<Bool>) {
        self.init(
            title: title,
            content: content,
            spacing: spacing,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            fullWidth: fullWidth,
            aligment: aligment
        ) {
            binding.wrappedValue.toggle()
        }
    }
    
    public init(title: String?, content: @escaping () -> Content, spacing: CGFloat = 0, maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil, fullWidth: Bool = false, aligment: Alignment = .center, action: @escaping VoidAction) {
        self.title     = title
        self.content   = content
        self.spacing   = spacing
        self.maxWidth  = maxWidth
        self.maxHeight = maxHeight
        self.fullWidth = fullWidth
        self.aligment  = aligment
        self.action    = action
    }
    
    public var body: some View {
        Button(action: action) {
            VStack(spacing: spacing) {
                content()
                if let title = title {                
                    Text(title)
                        .font(.appTextSmall)
                }
            }
            .frame(minWidth: maxWidth, minHeight: maxHeight, alignment: aligment)
            .if(fullWidth) { $0
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundColor(.textMain)
    }
}

extension LargeButton where Content == Image {
    public init(title: String?, image: Image, spacing: CGFloat = 0, maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil, fullWidth: Bool = false, aligment: Alignment = .center, binding: Binding<Bool>) {
        self.init(
            title: title,
            image: image,
            spacing: spacing,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            fullWidth: fullWidth,
            aligment: aligment
        ) {
            binding.wrappedValue.toggle()
        }
    }
    
    public init(title: String?, image: Image, spacing: CGFloat = 0, maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil, fullWidth: Bool = false, aligment: Alignment = .center, action: @escaping VoidAction) {
        self.init(
            title: title,
            content: { image },
            spacing: spacing,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            fullWidth: fullWidth,
            aligment: aligment,
            action: action
        )
    }
}

// MARK: - Previews -

struct ImageButton_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            HStack(alignment: .bottom) {
                LargeButton(title: "History", image: .asset(.history),   binding: .constant(true))
                LargeButton(title: "Invites", image: .asset(.invites),   binding: .constant(true))
//                LargeButton(title: "Give Kin", image: .asset(.kin),      binding: .constant(true))
//                LargeButton(title: "Give Kin", image: .asset(.kinLarge), spacing: 8, binding: .constant(true))
            }
        }
        .accentColor(.textMain)
    }
}
