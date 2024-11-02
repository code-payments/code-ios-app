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
import CodeServices

public struct GradientAvatarView: View {
    
    public let data: Data
    public let diameter: CGFloat
    
    // MARK: - Init -
    
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
    
    // MARK: - Body -
    
    public var body: some View {
        let (color1, color2) = generateColors(from: data)
        
        Canvas { context, size in
            let circlePath = Path(ellipseIn: CGRect(origin: .zero, size: size))
            context.fill(circlePath, with: .linearGradient(
                Gradient(colors: [color1, color2]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: diameter, y: diameter)
            ))
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            GeometryReader { geometry in
                let size = CGSize(
                    width: geometry.size.width * 0.4,
                    height: geometry.size.height * 0.4
                )
                
                Image.asset(.bubble)
                    .resizable()
                    .frame(
                        width: size.width,
                        height: size.height
                    )
                    .position(
                        x: (geometry.size.width  - size.width)  * 0.5 + size.width  * 0.5,
                        y: (geometry.size.height - size.height) * 0.5 + size.height * 0.5
                    )
            }
        }
        .drawingGroup()
    }
    
    private func generateColors(from data: Data) -> (Color, Color) {
        let halfIndex = data.count / 2
        let firstHalf = data.prefix(halfIndex)
        let secondHalf = data.suffix(from: halfIndex)
        
        return (colorHash(from: firstHalf), colorHash(from: secondHalf))
    }
    
    private func colorHash(from data: Data, saturation: Double = 1.0, brightness: Double = 1.0) -> Color {
        var hash = 0
        for byte in data {
            hash = Int(byte) + ((hash << 5) - hash)
        }
        
        let hue = Double((hash & 0xFFFFFF) % 360) / 360.0 // Generate hue from 0 to 1
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

//public struct GradientAvatarView: View {
//    
//    public let data: Data
//    public let diameter: CGFloat
//    
//    public init(data: Data, diameter: CGFloat) {
//        self.data = data
//        self.diameter = diameter
//    }
//    
//    public init(text: String, diameter: CGFloat) {
//        self.init(
//            data: Data(text.utf8),
//            diameter: diameter
//        )
//    }
//    
//    public init(uuid: UUID, diameter: CGFloat) {
//        self.init(
//            text: uuid.uuidString,
//            diameter: diameter
//        )
//    }
//    
//    public var body: some View {
//        Image(
//            uiImage: .generateAvatar(
//                data: data,
//                size: CGSize(width: diameter, height: diameter)
//            )
//        )
//        .mask(Circle())
//    }
//}
//
//extension UIImage {
//    
//    private static func colorHash(from data: Data, saturation: CGFloat = 1.0, brightness: CGFloat = 1.0) -> UIColor {
//        var hash = 0
//        for byte in data {
//            hash = Int(byte) + ((hash << 5) - hash)
//        }
//        
//        let hue = CGFloat((hash & 0xFFFFFF) % 360) / 360.0
//        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
//    }
//    
//    private static func generateColors(from data: Data) -> (UIColor, UIColor) {
//        let halfIndex = data.count / 2
//        let firstHalf = data.prefix(halfIndex)
//        let secondHalf = data.suffix(from: halfIndex)
//        
//        let color1 = colorHash(from: firstHalf)
//        let color2 = colorHash(from: secondHalf)
//        
//        return (color1, color2)
//    }
//    
//    static func generateAvatar(data: Data, size: CGSize) -> UIImage {
//
//        // Generate colors based on hashed data
//        let (color1, color2) = generateColors(from: data)
//        
//        let bounds = CGRect(origin: .zero, size: size)
//        
//        let renderer = UIGraphicsImageRenderer(bounds: bounds)
//        let image = renderer.image { c in
//            let context = c.cgContext
//            
//            // Create a linear gradient using the two generated colors
//            let cgColors = [color1.cgColor, color2.cgColor] as CFArray
//            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) else { return }
//            
//            // Draw the gradient diagonally from top-left to bottom-right
//            context.drawLinearGradient(
//                gradient,
//                start: CGPoint(x: bounds.minX, y: bounds.minY),
//                end: CGPoint(x: bounds.maxX, y: bounds.maxY),
//                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
//            )
//            
//            // Apply a circular mask to create a rounded avatar
//            let circlePath = UIBezierPath(ovalIn: bounds)
//            context.addPath(circlePath.cgPath)
//            context.clip()
//            context.drawPath(using: .fill)
//        }
//        
//        return image
//    }
//}

#Preview {
    GradientAvatarView(
        data: Data([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
        diameter: 50.0
    )
}
