//
//  ScrollBox.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct ScrollBox<Content>: View where Content: View {
    
    public var color: Color
    public var content: () -> Content
    
    private var gradient: Gradient {
        Gradient(colors: [
            color,
            color.opacity(0),
        ])
    }
    
    private var gradientHeight: CGFloat = 18
    
    // MARK: - Init -
    
    public init(color: Color, @ViewBuilder content: @escaping () -> Content) {
        self.color = color
        self.content = content
    }
    
    // MARK: - Body -
    
    public var body: some View {
        ZStack {
            content()
            VStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: gradient,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: gradientHeight, alignment: .center)
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: gradient,
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: gradientHeight, alignment: .center)
            }
            .edgesIgnoringSafeArea([.leading, .bottom, .trailing])
        }
    }
}

// MARK: - Previews -

struct ScrollBox_Previews: PreviewProvider {
    static var previews: some View {
        ScrollBox(color: .black) {
            List {
                Text("Row content")
                Text("Row content")
                Text("Row content")
                Text("Row content")
                Text("Row content")
                Text("Row content")
                Text("Row content")
                Text("Row content")
            }
        }
        .previewLayout(.fixed(width: 320, height: 300))
    }
}
