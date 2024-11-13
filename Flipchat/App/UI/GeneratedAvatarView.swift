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
import CodeUI
import FlipchatServices

public struct DeterministicAvatar: View {
    
    private let foregroundColor = Color(r: 255, g: 255, b: 255).opacity(0.9)
    private let backgroundColor = Color(r: 201, g: 214, b: 222)
    
    private let data: Data
    private let diameter: CGFloat
    
    public init(data: Data, diameter: CGFloat) {
        self.data = SHA512.digest(SHA512.digest(data))
        self.diameter = diameter
    }
    
    public var body: some View {
        VStack(spacing: diameter * 0.075) {
            
            UnevenRoundedCorners(
                tl: diameter * 0.25,
                bl: diameter * 0.1875,
                br: diameter * 0.1875,
                tr: diameter * 0.25
            )
            .fill(foregroundColor)
            .frame(width: diameter * 0.3125, height: diameter * 0.35)
            .padding(.top, diameter * 0.25)
            
            Circle()
                .fill(foregroundColor)
                .frame(width: diameter * 0.625, height: diameter * 0.625)
        }
        .frame(width: diameter, height: diameter, alignment: .top)
        .background(
            GradientAvatarView(
                data: data,
                diameter: diameter,
                showIcon: false
            )
        )
        .mask {
            Circle()
        }
        .drawingGroup()
    }
}

public struct DeterministicGradient: View {
    
    public let data: Data
    public let hash: Data
    public let start: UnitPoint
    public let end: UnitPoint
    
    public init(data: Data, start: UnitPoint = .top, end: UnitPoint = .bottom) {
        self.data  = data
        self.hash  = SHA512.digest(data)
        self.start = start
        self.end   = end
    }
    
    public var body: some View {
        let (color1, color2, color3) = Color.deterministicallyGenerate(from: hash.bytes)
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: color1, location: 0.14),
                .init(color: color2, location: 0.38),
                .init(color: color3, location: 0.67),
            ]),
            startPoint: start,
            endPoint: end
        )
        .overlay {
            GeometryReader { geometry in
                RadialGradient(
                    colors: [Color.white.opacity(0.25), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: geometry.size.height
                )
            }
        }
    }
}

public struct GradientAvatarView: View {
    
    public let data: Data
    public let hash: Data
    public let diameter: CGFloat
    public let showIcon: Bool
    
    // MARK: - Init -
    
    public init(data: Data, diameter: CGFloat, showIcon: Bool = true) {
        self.data = data
        self.hash = SHA512.digest(data)
        self.diameter = diameter
        self.showIcon = showIcon
    }
    
    public init(text: String, diameter: CGFloat, showIcon: Bool = true) {
        self.init(
            data: Data(text.utf8),
            diameter: diameter,
            showIcon: showIcon
        )
    }
    
    public init(uuid: UUID, diameter: CGFloat, showIcon: Bool = true) {
        self.init(
            text: uuid.uuidString,
            diameter: diameter,
            showIcon: showIcon
        )
    }
    
    // MARK: - Body -
    
    public var body: some View {
        let (color1, color2, color3) = Color.deterministicallyGenerate(from: hash.bytes)
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: color1, location: 0.14),
                .init(color: color2, location: 0.38),
                .init(color: color3, location: 0.67),
            ]),
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            if showIcon {
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
        }
        .drawingGroup()
    }
}

private extension Color {
    static func deterministicallyGenerate(from bytes: [UInt8]) -> (Color, Color, Color) {
        
        let hue = CGFloat(bytes.prefix(3).reduce(0) { $0 + Int($1) } % 360) / 360.0
        let saturation: CGFloat = 0.75
        let baseBrightness: CGFloat = 0.85
        let brightnessVariation: CGFloat = CGFloat(bytes[3] % 10) / 100.0
        let hueShift: CGFloat = 20 / 360.0
        
        let startColor = Color(
            hue: hue,
            saturation: saturation.clamped(to: 0...1),
            brightness: (baseBrightness - brightnessVariation).clamped(to: 0...1)
        )
        
        let middleColor = Color(
            hue: (hue + hueShift).truncatingRemainder(dividingBy: 1),
            saturation: (saturation * 0.95).clamped(to: 0...1),
            brightness: baseBrightness.clamped(to: 0...1)
        )
        
        let endColor = Color(
            hue: (hue + hueShift * 2).truncatingRemainder(dividingBy: 1),
            saturation: (saturation * 0.9).clamped(to: 0...1),
            brightness: (baseBrightness + brightnessVariation).clamped(to: 0...1)
        ).ensureReadableWithWhite()
        
        return (startColor, middleColor, endColor)
    }
}

private extension Color {
    
    /// Calculates the luminance of a color using its RGB components
    private func relativeLuminance() -> CGFloat {
        guard let components = self.rgbComponents else {
            return 0
        }
        
        func adjust(_ value: CGFloat) -> CGFloat {
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        
        let r = adjust(components.r)
        let g = adjust(components.g)
        let b = adjust(components.b)
        
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    
    /// Calculates the contrast ratio with white color
    func contrastRatioWithWhite() -> CGFloat {
        let whiteLuminance: CGFloat = 1.0
        let colorLuminance = self.relativeLuminance()
        
        if whiteLuminance > colorLuminance {
            return (whiteLuminance + 0.05) / (colorLuminance + 0.05)
        } else {
            return (colorLuminance + 0.05) / (whiteLuminance + 0.05)
        }
    }

    /// Adjusts color to meet contrast requirements for readability with white
    func ensureReadableWithWhite() -> Color {
        var adjustedColor = self
        var attempts = 0
        // WCAG AA requires contrast ratio of 4.5:1 for normal text
        while adjustedColor.contrastRatioWithWhite() < 4.5 && attempts < 10 {
            // Darken the color by reducing its brightness in HSB
            if let components = adjustedColor.hsbaComponents {
                adjustedColor = Color(
                    hue: components.h,
                    saturation: components.s,
                    brightness: (components.b * 0.9).clamped(to: 0...1)
                )
            }
            attempts += 1
        }
        return adjustedColor
    }

    /// Extracts RGB components from a Color
    var rgbComponents: (r: CGFloat, g: CGFloat, b: CGFloat)? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return nil
        }
        
        return (r, g, b)
    }

    /// Extracts HSBA components from a Color
    var hsbaComponents: (h: CGFloat, s: CGFloat, b: CGFloat, a: CGFloat)? {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return nil
        }
        
        return (h, s, b, a)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

#Preview {
    GradientAvatarView(
        data: Data([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
        diameter: 50.0
    )
}
