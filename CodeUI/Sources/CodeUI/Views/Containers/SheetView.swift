//
//  SheetView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct SheetView<Content>: View where Content: View {
    
    private var edge: Edge
    private var backgroundColor: Color
    private var content: () -> Content
    
    // MARK: - Init -
    
    public init(edge: Edge, backgroundColor: Color, @ViewBuilder content: @escaping () -> Content) {
        self.edge = edge
        self.backgroundColor = backgroundColor
        self.content = content
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 0) {
            if edge == .bottom {
                Spacer()
            }
            
            content()
                .frame(maxWidth: .infinity)
                .background(
                    backgroundColor
                        .clipShape(clip())
                        .edgesIgnoringSafeArea(.all)
                )
            
            if edge == .top {
                Spacer()
            }
        }
        .animation(.easeOutSlower)
        .transition(
            AnyTransition
                .move(edge: edge)
        )
    }
    
    private func safeAreaOffset(for edge: Edge, geometry: GeometryProxy) -> CGSize {
        CGSize(
            width: 0,
            height: edge == .top ? geometry.safeAreaInsets.top : geometry.safeAreaInsets.bottom
        )
    }
    
    // MARK: - Clip -
    
    private func clip() -> some Shape {
        RoundedCorners(
            radius: 10.0,
            corners: cornersForClip()
        )
    }
    
    private func cornersForClip() -> UIRectCorner {
        switch edge {
        case .top, .leading:
            return [.bottomLeft, .bottomRight]
            
        case .bottom, .trailing:
            return [.topLeft, .topRight]
        }
    }
}

// MARK: - RoundedCorners -

private struct RoundedCorners: Shape {
    
    let radius: CGFloat
    let corners: UIRectCorner
    
    init(radius: CGFloat, corners: UIRectCorner) {
        self.radius = radius
        self.corners = corners
    }
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(
                width: radius,
                height: radius
            )
        )
        
        return Path(path.cgPath)
    }
}

// MARK: - Previews -

struct SheetView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SheetView(edge: .bottom, backgroundColor: .backgroundMain) {
                VStack {
                    Text("Title")
                        .padding(5)
                    Text("Subtitle")
                        .padding(5)
                }
                .foregroundColor(.textMain)
            }
            SheetView(edge: .top, backgroundColor: .backgroundMain) {
                VStack {
                    Text("Title")
                        .padding(5)
                    Text("Subtitle")
                        .padding(5)
                }
                .foregroundColor(.red)
            }
        }
        .previewLayout(.fixed(width: 200.0, height: 100.0))
    }
}

#endif
