//
//  Hex.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Hex: Shape {
    
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let center  = CGPoint(x: rect.midX, y: rect.midY)
        let size    = min(rect.width, rect.height) / 2.0
        let corners = (0..<6).map { index in
            let angle = CGFloat.pi / 3 * CGFloat(index)
            return CGPoint(
                x: center.x + size * sin(angle),
                y: center.y + size * cos(angle)
            )
        }
        
        corners.enumerated().forEach { index, point in
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        
        path.closeSubpath()
        return path
    }
}
