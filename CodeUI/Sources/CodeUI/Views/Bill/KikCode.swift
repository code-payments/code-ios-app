//
//  KikCode.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI
import CoreGraphics

enum KikCode {
        
    static let innerRingRatio: CGFloat = 0.32
    static let firstRingRatio: CGFloat = 0.425
    static let lastRingRatio:  CGFloat = 0.95
    
    static let scaleFactor: CGFloat = 8.0
    
    static let ringCount: Int = 6
    
    static func generateDescription(size: CGSize, payload: Payload) throws -> Description {
        let dimension = min(size.width, size.height)
        
        guard dimension > 0 else {
            throw Error.invalidSize
        }
        
        guard payload.data.count > 0 else {
            throw Error.emptyData
        }
        
        guard payload.data.count < 40 else {
            throw Error.dataTooLong
        }
        
        let byteArray = payload.data.map { UInt8($0) }
        
        let center = CGPoint(
            x: dimension * 0.5,
            y: dimension * 0.5
        )
        
        let outerRingWidth = dimension * 0.5
        let innerRingWidth = KikCode.innerRingRatio * outerRingWidth
        let firstRingWidth = KikCode.firstRingRatio * outerRingWidth
        let lastRingWidth  = KikCode.lastRingRatio  * outerRingWidth
        
        let centerPath = UIBezierPath()
        var dots: [UIBezierPath] = []
        var arcs: [UIBezierPath] = []
        
        // Then draw the inner circle
        centerPath.addArc(
            withCenter: center,
            radius: innerRingWidth,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: false
        )
        
        let ringWidth = (lastRingWidth - firstRingWidth) / CGFloat(KikCode.ringCount)
        let dotSize = ringWidth * 3 / 4
        
        var offset = 0
        
        // Modeled after the reference python implementation for drawing a Kik code
        // The general gist: iterate through all the rings that we need to draw, and for each ring
        // walk through their corresponding bits from byteArray[]. If a bit is set -- draw a dot, if the next bit is also set
        // draw a connecting arc to the next dot (which is drawn on the next iteration)
        for ring in 0..<KikCode.ringCount {
            var r = ringWidth * CGFloat(ring) + firstRingWidth
            if ring == 0 {
                r = r - innerRingWidth / 10
            }
            
            let n = KikCode.scaleFactor * CGFloat(ring) + 32
            let delta = CGFloat.pi * 2 / n
            
            let startOffset = offset
            
            for a in 0..<Int(n) {
                let angle = CGFloat(a) * delta - .pi / 2
                
                let bitMask = 0x1 << (offset % 8)
                let byteIndex = offset / 8
                let currentBit = byteIndex < byteArray.count && (Int(byteArray[byteIndex]) & bitMask != 0)
                
                if currentBit {
                    let radius = (r + ringWidth / 2)
                    let xc = center.x + radius * cos(angle)
                    let yc = center.y + radius * sin(angle)
                    let arcCenter = CGPoint(x: xc, y: yc)
                    
                    let dot = UIBezierPath()
                    dot.addArc(
                        withCenter: arcCenter,
                        radius: dotSize * 0.5,
                        startAngle: 0,
                        endAngle: .pi * 2,
                        clockwise: false
                    )
                    dots.append(dot)
                    
                    let nextOffset = (offset - startOffset + 1) % Int(n) + startOffset
                    let nextBitMask = 0x1 << (nextOffset % 8)
                    let nextIndex = nextOffset / 8
                    let nextBit = nextIndex < byteArray.count && (Int(byteArray[nextIndex]) & nextBitMask != 0)
                    
                    if nextBit {
                        let arc = UIBezierPath()
                        arc.addArc(
                            withCenter: center,
                            radius: radius,
                            startAngle: angle,
                            endAngle: angle + delta,
                            clockwise: true
                        )
                        arcs.append(arc)
                    }
                }
                
                offset += 1
            }
        }
        
        return Description(
            size: CGSize(width: dimension, height: dimension),
            center: centerPath,
            dots: dots,
            arcs: arcs,
            dotDimension: dotSize
        )
    }
}

// MARK: - Payload -

extension KikCode {
    struct Payload {
        
        let data: Data
        
        init(_ data: Data) {
            var payload = Data([0xB2, 0xCB, 0x25, 0xC6]) // Finder bytes
            payload.append(data)
            self.data = payload
        }
    }
}

// MARK: - Description -

extension KikCode {
    struct Description {
        var size: CGSize
        var center: UIBezierPath
        var dots: [UIBezierPath]
        var arcs: [UIBezierPath]
        var dotDimension: CGFloat
    }
}

// MARK: - Error -

extension KikCode {
    enum Error: Swift.Error {
        case invalidSize
        case emptyData
        case dataTooLong
    }
}

#endif
