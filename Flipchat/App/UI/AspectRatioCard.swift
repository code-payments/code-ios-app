//
//  AspectRatioCard.swift
//  Code
//
//  Created by Dima Bart on 2024-11-20.
//

import SwiftUI

struct AspectRatioCard<Content>: View where Content: View {
    
    private let padding: CGFloat = 20
    private let ratio: CGFloat = 1.647
    
    public let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = size(for: geometry)
            
            content()
                .frame(width: size.width, height: size.height)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.25), radius: 40)
                .position(position(for: geometry, size: size))
        }
    }

    private func size(for geometry: GeometryProxy) -> CGSize {
        var h = geometry.size.height - padding * 2
        var w = h / ratio
        
        if w + padding * 2 > geometry.size.width {
            w = geometry.size.width - padding * 2
            h = w * ratio
        }
        
        return .init(
            width: max(w, 0),
            height: max(h, 0)
        )
    }
    
    private func position(for geometry: GeometryProxy, size: CGSize) -> CGPoint {
        let y = (geometry.size.height - size.height) * 0.5 + size.height * 0.5
        let x = (geometry.size.width  - size.width)  * 0.5 + size.width  * 0.5
        
        return .init(x: x, y: y)
    }
}
