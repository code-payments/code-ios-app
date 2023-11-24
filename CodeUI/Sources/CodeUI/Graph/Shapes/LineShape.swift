//
//  LineShape.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

struct LineShape: Shape {
    
    let normalizedPoints: [Double]
    let smooth: Bool
    
    // MARK: - Init -
    
    init(normalizedPoints: [Double], smooth: Bool) {
        self.normalizedPoints = normalizedPoints
        self.smooth = smooth
    }
    
    // MARK: - Path -
    
    func path(in rect: CGRect) -> Path {
        guard !normalizedPoints.isEmpty else {
            return Path()
        }
        
        let count = CGFloat(normalizedPoints.count - 1)
        
        let xInterval: CGFloat = rect.width / count
        
        var path = Path()

        let points = normalizedPoints.enumerated().map { index, point in
            CGPoint(
                x: xInterval * CGFloat(index),
                y: rect.height - CGFloat(point) * rect.height
            )
        }
        
        if !smooth {
            path.addLines(points)
        } else {
            var previousPoint: CGPoint?
            var hasStart: Bool = false
            points.forEach { point in
                if let previousPoint = previousPoint {
                    let midPoint = CGPoint(
                        x: (point.x + previousPoint.x) * 0.5,
                        y: (point.y + previousPoint.y) * 0.5
                    )
                    
                    if hasStart {
                        path.addQuadCurve(to: midPoint, control: previousPoint)
                    } else {
                        path.addLine(to: midPoint)
                    }
                    
                } else {
                    path.move(to: point)
                    hasStart = true
                }
                
                previousPoint = point
            }
            
            if let previousPoint = previousPoint {
                path.addLine(to: previousPoint)
            }
        }
        
        return path
    }
}
