//
//  CustomPanelView.swift
//  ColorPicker
//
//  Created by Aiden Walker on 2025-10-22.
//

import SwiftUI
import UIKit

// MARK: - Custom Panel View

struct CustomPanelView: View {
    @Binding var hue: CGFloat
    @Binding var saturation: CGFloat
    @Binding var brightness: CGFloat
    var onBack: () -> Void
    
    var body: some View {
        HStack(spacing: PanelMetrics.spacing) {
            SaturationBrightnessSquare(
                hue: $hue,
                saturation: $saturation,
                brightness: $brightness
            )
            .frame(maxHeight: .infinity)
            .zIndex(1) // Higher z-index to appear above hue slider
            
            HueScroller(
                hue: $hue,
                saturation: saturation,
                brightness: brightness
            )
            .frame(maxHeight: .infinity)
            .zIndex(0) // Lower z-index to appear below sat/brightness pad
            
            Button(action: onBack) {
                BackButton()
            }
            .buttonStyle(.plain)
            .frame(width: 48)
        }
    }
}

// MARK: - Saturation/Brightness Square

struct SaturationBrightnessSquare: View {
    @Binding var hue: CGFloat
    @Binding var saturation: CGFloat
    @Binding var brightness: CGFloat
    
    @State private var isDragging: Bool = false
    @State private var hapticTrigger: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let radius: CGFloat = PanelMetrics.cornerRadius
            
            ZStack {
                // Base: hue-colored background
                LinearGradient(colors: [
                    Color(hue: hue, saturation: 0, brightness: 1),
                    Color(hue: hue, saturation: 1, brightness: 1)
                ], startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                
                // Overlay: brightness vertical gradient
                LinearGradient(colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(1)
                ], startPoint: .top, endPoint: .bottom)
                .blendMode(.multiply)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                
                // Dot grid overlay
                DotGrid(
                    columns: 8,
                    rows: 6,
                    dotSize: 2,
                    inset: 12,
                    color: Color.white.opacity(0.09)
                )
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.tertiary, lineWidth: 1)
            )
            // Thumb overlay
            .overlay(alignment: .topLeading) {
                let x = saturation * size.width
                let y = (1 - brightness) * size.height
                
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                        .background(
                            Circle()
                                .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                        )
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                        .scaleEffect(isDragging ? 1.2 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7, blendDuration: 0.1), value: isDragging)
                }
                .frame(width: 26, height: 26)
                .offset(x: x - 13, y: y - 13)
            }
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(white: 0.12))
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        hapticTrigger.toggle()
                    }
                    update(from: value.location, in: size)
                }
                .onEnded { value in
                    update(from: value.location, in: size)
                    isDragging = false
                })
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        }
    }
    
    private func update(from point: CGPoint, in size: CGSize) {
        let x = max(0, min(size.width, point.x))
        let y = max(0, min(size.height, point.y))
        saturation = size.width == 0 ? 0 : x / size.width
        brightness = size.height == 0 ? 0 : 1 - (y / size.height)
    }
}

// MARK: - Hue Scroller

struct HueScroller: View {
    @Binding var hue: CGFloat
    var saturation: CGFloat
    var brightness: CGFloat
    
    @State private var lastDragLocation: CGFloat?
    @State private var isDragging: Bool = false
    @State private var hapticTrigger: Bool = false
    @State private var tickHapticTrigger: Bool = false
    @State private var lastTickIndex: Int?
    @Environment(\.displayScale) private var displayScale
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let radius: CGFloat = PanelMetrics.cornerRadius
            let sensitivity: CGFloat = 0.25
            
            ZStack {
                // Procedural hue strip
                Canvas { ctx, size in
                    let w = size.width
                    let h = size.height
                    let pixelsPerHue = w / max(sensitivity, 0.0001)
                    let step: CGFloat = max(1, displayScale == 0 ? 1 : (1 / displayScale))
                    
                    var x: CGFloat = 0
                    while x < w {
                        let localHue = hue + (x - w/2) / pixelsPerHue
                        var wrapped = localHue.truncatingRemainder(dividingBy: 1)
                        if wrapped < 0 { wrapped += 1 }
                        let rect = CGRect(x: x, y: 0, width: step, height: h)
                        ctx.fill(Path(rect), with: .color(Color(hue: wrapped, saturation: saturation, brightness: brightness)))
                        x += step
                    }
                    
                    // Tick marks
                    let tickCount = 12
                    let tickHeight = h * 0.4
                    let tickWidth: CGFloat = 2
                    let spacing = w / CGFloat(tickCount)
                    let phase = (hue * pixelsPerHue).truncatingRemainder(dividingBy: spacing)
                    for i in 0...tickCount {
                        let tx = CGFloat(i) * spacing - phase
                        let tickRect = CGRect(x: tx - tickWidth/2, y: (h - tickHeight)/2, width: tickWidth, height: tickHeight)
                        let tickPath = Path(roundedRect: tickRect, cornerRadius: 1)
                        ctx.fill(tickPath, with: .color(Color.white.opacity(0.25)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.tertiary, lineWidth: 1)
                )
                
                // Fixed centered thumb
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                        .frame(width: 12, height: 80)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 3)
                        .frame(width: 12, height: 80)
                }
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                .scaleEffect(isDragging ? 1.1 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7, blendDuration: 0.1), value: isDragging)
                .allowsHitTesting(false)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.4), trigger: tickHapticTrigger)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            hapticTrigger.toggle()
                        }
                        handleDrag(value: value, width: width, sensitivity: sensitivity)
                    }
                    .onEnded { _ in
                        lastDragLocation = nil
                        isDragging = false
                        lastTickIndex = nil
                    }
            )
        }
    }
    
    private func handleDrag(value: DragGesture.Value, width: CGFloat, sensitivity: CGFloat) {
        if let lastX = lastDragLocation {
            let delta = value.location.x - lastX
            let hueDelta = width == 0 ? 0 : (-delta / width) * sensitivity
            var newHue = hue + hueDelta
            if newHue < 0 { newHue += 1 }
            if newHue > 1 { newHue -= 1 }
            hue = newHue
            
            // Tick-crossing haptic
            let pixelsPerHue = width / max(sensitivity, 0.0001)
            let tickCount = 12
            let spacing = width / CGFloat(tickCount)
            let currentIndex = Int(((hue * pixelsPerHue) / spacing).rounded(.towardZero))
            if lastTickIndex == nil { lastTickIndex = currentIndex }
            if lastTickIndex != currentIndex {
                tickHapticTrigger.toggle()
                lastTickIndex = currentIndex
            }
        }
        lastDragLocation = value.location.x
    }
}

// MARK: - Supporting Views

struct BackButton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
            .fill(Color(white: 0.2))
            .overlay(
                Image(systemName: "chevron.right")
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .semibold))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(.tertiary, lineWidth: 1)
            )
    }
}

struct DotGrid: View {
    let columns: Int
    let rows: Int
    let dotSize: CGFloat
    let inset: CGFloat
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            
            let usableWidth = width - inset * 2
            let usableHeight = height - inset * 2
            
            let hSpacing = columns > 1 ? (usableWidth - CGFloat(columns) * dotSize) / CGFloat(columns - 1) : 0
            let vSpacing = rows > 1 ? (usableHeight - CGFloat(rows) * dotSize) / CGFloat(rows - 1) : 0
            
            Canvas { ctx, _ in
                for col in 0..<columns {
                    for row in 0..<rows {
                        let x = inset + CGFloat(col) * (dotSize + hSpacing) + dotSize / 2
                        let y = inset + CGFloat(row) * (dotSize + vSpacing) + dotSize / 2
                        let circle = Path(ellipseIn: CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize))
                        ctx.fill(circle, with: .color(color))
                    }
                }
            }
        }
    }
}
