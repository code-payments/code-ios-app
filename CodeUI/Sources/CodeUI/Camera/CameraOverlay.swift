//
//  CameraOverlay.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct CameraOverlay: View {
    
    private let edgePadding: CGFloat = 40.0
    
    public init() {}
    
    private let verticalOffset: CGFloat = -50
    
    public var body: some View {
        ZStack {
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.cameraOverlay)
                    .mask(
                        clipPath(in: CGRect(origin: .zero, size: geometry.size))
                            .fill(style: FillStyle(eoFill: true))
                    )
            }
            Circle()
                .inset(by: edgePadding)
                .offset(x: 0, y: verticalOffset)
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 2.0, antialiased: true)
        }
    }
    
    func clipPath(in rect: CGRect) -> Path {
        let rectangle = Rectangle()
        let circle = Circle()
        
        let clipRect = rect
            .insetBy(dx: edgePadding, dy: edgePadding)
            .offsetBy(dx: 0, dy: verticalOffset)
        
        var path = rectangle.path(in: rect)
        path.addPath(circle.path(in: clipRect))
        
        return path
    }
}

// MARK: - Previews -

struct CameraOverlay_Previews: PreviewProvider {
    static var previews: some View {
        CameraOverlay()
            .background(Color.blue)
            .edgesIgnoringSafeArea(.all)
    }
}
