//
//  UnevenRoundedCorners.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct UnevenRoundedCorners: Shape {
    
    public var tl: CGFloat = 0.0
    public var bl: CGFloat = 0.0
    public var br: CGFloat = 0.0
    public var tr: CGFloat = 0.0
    
    public init(tl: CGFloat, bl: CGFloat, br: CGFloat, tr: CGFloat) {
        self.tl = tl
        self.bl = bl
        self.br = br
        self.tr = tr
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.size.width
        let h = rect.size.height

        // Make sure we do not exceed the size of the rectangle
        let tr = min(min(self.tr, h * 0.5), w * 0.5)
        let tl = min(min(self.tl, h * 0.5), w * 0.5)
        let bl = min(min(self.bl, h * 0.5), w * 0.5)
        let br = min(min(self.br, h * 0.5), w * 0.5)
        
        path.move(to: CGPoint(x: w / 2.0, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(
            center: CGPoint(x: w - tr, y: tr),
            radius: tr,
            startAngle: Angle(degrees: -90),
            endAngle: Angle(degrees: 0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(
            center: CGPoint(x: w - br, y: h - br),
            radius: br,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(
            center: CGPoint(x: bl, y: h - bl),
            radius: bl,
            startAngle: Angle(degrees: 90),
            endAngle: Angle(degrees: 180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(
            center: CGPoint(x: tl, y: tl),
            radius: tl,
            startAngle: Angle(degrees: 180),
            endAngle: Angle(degrees: 270),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}
