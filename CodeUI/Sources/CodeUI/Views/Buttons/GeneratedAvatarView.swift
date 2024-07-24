//
//  GeneratedAvatarView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CommonCrypto
import SwiftUI

public struct GeneratedAvatarView: View {
    
    public let data: Data
    public let diameter: CGFloat
    
    public init(data: Data, diameter: CGFloat) {
        self.data = data
        self.diameter = diameter
    }
    
    public init(text: String, diameter: CGFloat) {
        self.init(
            data: Data(text.utf8),
            diameter: diameter
        )
    }
    
    public init(uuid: UUID, diameter: CGFloat) {
        self.init(
            text: uuid.uuidString,
            diameter: diameter
        )
    }
    
    public var body: some View {
        Image(
            uiImage: .generateAvatar(
                data: data,
                size: CGSize(width: diameter, height: diameter)
            )
        )
        .mask(Circle())
    }
}

extension UIImage {
    static func generateAvatar(data: Data, size: CGSize) -> UIImage {
        
        let hash = data.sha512()
        
        let backgroundColor = UIColor(r: 230, g: 240, b: 250)
        let foregroundColor = UIColor.rgb(from: Array(hash.prefix(3)))
        
        let bounds  = CGRect(
            origin: .zero,
            size: size
        )
        
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { c in
            let context = c.cgContext
            
            context.setFillColor(backgroundColor.cgColor)
            context.fill(bounds)
            
            let length   = 10
            let rCount   = length
            let cCount   = length / 2
            let cellSize = size.width / CGFloat(length)
            let inset    = cellSize * 0.8
            
            let full = UIBezierPath(ovalIn: bounds)
            let mask = UIBezierPath(
                ovalIn:
                    bounds.insetBy(
                        dx: inset,
                        dy: inset
                    )
            )
            
            let delta = full.cgPath.subtracting(mask.cgPath)
            
            context.saveGState()
            
            var paths: [UIBezierPath] = []
            
            for r in 0..<rCount {
                for c in 0..<cCount {
                    let i = r * cCount + c
                    
                    let isEven = hash[i] % 2 == 0
                    if isEven {
                        let leftPath = path(
                            row: r,
                            col: c,
                            size: cellSize,
                            color: foregroundColor
                        )
                        
                        if !delta.intersects(leftPath.cgPath) {
                            paths.append(leftPath)
                        }
                        
                        let rightPath = path(
                            row: r,
                            col: length - c - 1,
                            size: cellSize,
                            color: foregroundColor
                        )
                        
                        if !delta.intersects(rightPath.cgPath) {
                            paths.append(rightPath)
                        }
                    }
                }
            }
            
            paths.forEach {
                context.addPath($0.cgPath)
            }
            
            context.setFillColor(foregroundColor.cgColor)
            context.fillPath(using: .winding)
            
            context.restoreGState()
            
//            let outsidePath = UIBezierPath(ovalIn: bounds)
//            let insidePath  = UIBezierPath(
//                ovalIn: bounds.insetBy(
//                    dx: cellSize,
//                    dy: cellSize
//                )
//            )
//
//            let borderPath = outsidePath.cgPath.subtracting(insidePath.cgPath, using: .evenOdd)
//
//            context.addPath(borderPath)
//            context.setFillColor(shapeColor.cgColor)
//            context.fillPath(using: .winding)
        }
        
        return image
}
    
    private static func path(row: Int, col: Int, size: CGFloat, color: UIColor) -> UIBezierPath {
        UIBezierPath(rect:
            CGRect(
                x: CGFloat(col) * size,
                y: CGFloat(row) * size,
                width: size,
                height: size
            )
        )
    }
}

private extension UUID {
    var data: Data {
        let b = uuid
        return Data([
            b.0,  b.1,  b.2,  b.3,
            b.4,  b.5,  b.6,  b.7,
            b.8,  b.9,  b.10, b.11,
            b.12, b.13, b.14, b.15,
        ])
    }
}

private extension Data {
    func sha512() -> [UInt8] {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        withUnsafeBytes {
            _ = CC_SHA512($0.baseAddress, CC_LONG(count), &hash)
        }
        return hash
    }
}

private extension String {
    func sha512() -> [UInt8] {
        Data(utf8).sha512()
    }
}

private extension UIColor {
    static func rgb(from hex: [UInt8]) -> UIColor {
        UIColor(
            red:   CGFloat(hex[0]) / 255.0 * 1.3,
            green: CGFloat(hex[1]) / 255.0 * 1.1,
            blue:  CGFloat(hex[2]) / 255.0 * 1.3,
            alpha: 1.0
        )
    }
}
