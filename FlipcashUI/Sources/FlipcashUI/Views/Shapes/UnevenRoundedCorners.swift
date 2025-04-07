//
//  UnevenRoundedCorners.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct UnevenRoundedCorners: InsettableShape {
    
    public var tl: CGFloat = 0.0
    public var bl: CGFloat = 0.0
    public var br: CGFloat = 0.0
    public var tr: CGFloat = 0.0
    
    public var inset: CGFloat = 0.0
    
    public init(tl: CGFloat, bl: CGFloat, br: CGFloat, tr: CGFloat, inset: CGFloat = 0) {
        self.tl = tl
        self.bl = bl
        self.br = br
        self.tr = tr
        self.inset = inset
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let insetRect = rect.insetBy(dx: inset, dy: inset)
        let w = insetRect.size.width
        let h = insetRect.size.height

        let x = insetRect.minX
        let y = insetRect.minY

        let tr = min(min(self.tr, h * 0.5), w * 0.5)
        let tl = min(min(self.tl, h * 0.5), w * 0.5)
        let bl = min(min(self.bl, h * 0.5), w * 0.5)
        let br = min(min(self.br, h * 0.5), w * 0.5)
        
        path.move(to: CGPoint(x: x + w / 2.0, y: y))
        path.addLine(to: CGPoint(x: x + w - tr, y: y))
        path.addArc(
            center: CGPoint(x: x + w - tr, y: y + tr),
            radius: tr,
            startAngle: Angle(degrees: -90),
            endAngle: Angle(degrees: 0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: x + w, y: y + h - br))
        path.addArc(
            center: CGPoint(x: x + w - br, y: y + h - br),
            radius: br,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: x + bl, y: y + h))
        path.addArc(
            center: CGPoint(x: x + bl, y: y + h - bl),
            radius: bl,
            startAngle: Angle(degrees: 90),
            endAngle: Angle(degrees: 180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: x, y: y + tl))
        path.addArc(
            center: CGPoint(x: x + tl, y: y + tl),
            radius: tl,
            startAngle: Angle(degrees: 180),
            endAngle: Angle(degrees: 270),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
    
    public func inset(by amount: CGFloat) -> UnevenRoundedCorners {
        var shape = self
        shape.inset += amount
        return shape
    }
}
