//
//  RectEdgeShape.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct RectEdgeShape: Shape, InsettableShape {

    public var edge: UIRectEdge
    public var insets: CGFloat
    
    public init(edge: UIRectEdge, insets: CGFloat = 0) {
        self.edge = edge
        self.insets = insets
    }

    public func path(in rect: CGRect) -> Path {
        Path(drawPath(for: edge, in: rect.insetBy(dx: insets, dy: insets)))
    }
    
    public func inset(by amount: CGFloat) -> RectEdgeShape {
        RectEdgeShape(edge: edge, insets: insets + amount)
    }
            
    private func drawPath(for edge: UIRectEdge, in rect: CGRect) -> CGPath {
        let path = UIBezierPath()
        
        if edge.contains(.top) {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        
        if edge.contains(.left) {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        
        if edge.contains(.bottom) {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        
        if edge.contains(.right) {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        
        return path.cgPath
    }
}
