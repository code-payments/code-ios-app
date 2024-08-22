//
//  Badged.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Badged: ViewModifier {
    
    public var count: Int
    public var size: Bubble.Size
    public var insets: EdgeInsets
    public var reverseX: Bool
    public var reverseY: Bool
    
    public init(count: Int, size: Bubble.Size, insets: EdgeInsets, reverseX: Bool, reverseY: Bool) {
        self.count = count
        self.size = size
        self.insets = insets
        self.reverseX = reverseX
        self.reverseY = reverseY
    }
    
    public func body(content: Content) -> some View {
        content .overlay(
            HStack {
                if !reverseX {
                    Spacer()
                }
                VStack {
                    if reverseY {
                        Spacer()
                    }
                    
                    Bubble(size: size, count: count)
                        .fixedSize()
                    
                    if !reverseY {
                        Spacer()
                    }
                }
                if reverseX {
                    Spacer()
                }
            }
            .padding(size.dimension * -0.5)
            .padding(insets)
        )
    }
}

extension EdgeInsets {
    public static let zero = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

// MARK: - View -

extension View {
    public func badged(_ count: Int, size: Bubble.Size = .extraLarge, insets: EdgeInsets = .zero, reverseX: Bool = false, reverseY: Bool = false) -> some View {
        modifier(
            Badged(
                count: count,
                size: size,
                insets: insets,
                reverseX: reverseX,
                reverseY: reverseY
            )
        )
    }
}

// MARK: - Previews -

struct Badged_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .blue) {
            Button {
                // Do nothing
            } label: {
                Rectangle()
                    .fill(.red)
                    .frame(width: 60, height: 60)
            }
            .badged(3, insets: .init(top: 0, leading: 20, bottom: 0, trailing: 10), reverseX: true, reverseY: false)
        }
    }
}
