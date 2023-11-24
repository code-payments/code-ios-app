//
//  VerticalContainer.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct VerticalContainer<T>: View where T: View {
    
    public let angle: Angle
    public let content: () -> T
    
    // MARK: - Init -
    
    public init(angle: Angle, @ViewBuilder content: @escaping () -> T) {
        self.angle = angle
        self.content = content
    }
    
    // MARK: - Body -
    
    public var body: some View {
        GeometryReader { geometry in
            Group {
                content()
                    .rotationEffect(angle)
                    .frame(width: geometry.size.height, height: geometry.size.width)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
