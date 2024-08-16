//
//  Hex.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Hex: Shape {
    
    public let stroke: CGFloat?
    
    public init(stroke: CGFloat? = nil) {
        self.stroke = stroke
    }
    
    public func path(in rect: CGRect) -> Path {
        if let stroke {
            return .hexIn(rect: rect).strokedPath(
                .init(
                    lineWidth: stroke,
                    lineCap: .round,
                    lineJoin: .miter
                )
            )
        } else {
            return .hexIn(rect: rect)
        }
    }
}

extension Path {
    static func hexIn(rect: CGRect) -> Path {
        let size   = min(rect.width, rect.height) / 2.0
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        var path = Path()
        
        (0..<6).map { index in
            let angle = CGFloat.pi / 3 * CGFloat(index)
            return CGPoint(
                x: center.x + size * sin(angle),
                y: center.y + size * cos(angle)
            )
        }.enumerated().forEach { index, point in
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
