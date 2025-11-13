//
//  ColorEditorControl.swift
//  Code
//
//  Created by Dima Bart on 2025-11-07.
//

import Foundation
import SwiftUI
import UIKit

public struct ColorEditorControl: View {
    
    @Binding private var colors: [Color]
    
    @State private var stops: [GradientStop]
    @State private var selectedIndex: Int = 0
    @State private var pressedSwatchIndex: Int?
    @State private var bouncingSwatchIndex: Int?
    @State private var mode: PickerMode = .presets
    
    private let maxStops: Int = 3
    
    // MARK: - Init -
    
    public init(color: Binding<Color>) {
        self._colors = Binding<[Color]>(
            get: { [color.wrappedValue] },
            set: { colors in
                if let first = colors.first {
                    color.wrappedValue = first
                }
            }
        )
        
        self._stops = State(
            initialValue: [
                GradientStop(from: color.wrappedValue)
            ]
        )
    }
    
    public init(colors: Binding<[Color]>) {
        let initialColors = Array(colors.wrappedValue.prefix(3).reversed())
        self._colors      = colors
        self._stops       = State(
            initialValue: initialColors.isEmpty ? [
                GradientStop(hue: 0.6, saturation: 0.7, brightness: 0.9)
            ] : initialColors.map {
                GradientStop(from: $0)
            }
        )
    }
    
    public var body: some View {
        VStack(spacing: 15) {
            
            // Preview
//            previewView
//                .frame(maxHeight: 100)
//                .overlay(previewBorder)
            
            // Gradient stops row
            HStack(spacing: 8) {
                removeButton
                swatchRow
                addButton
            }
            
            // Sliding panels
            panelContainer
        }
        .padding(20)
        .onChange(of: stops) { _, newStops in
            colors = newStops.map(\.color).reversed()
        }
    }
}

// MARK: - Internal Models

private enum PickerMode {
    case presets
    case custom
}

private struct GradientStop: Identifiable, Equatable {
    let id = UUID()
    var hue: CGFloat
    var saturation: CGFloat
    var brightness: CGFloat
    var alpha: CGFloat = 1.0
    
    var color: Color { 
        Color(hue: hue, saturation: saturation, brightness: brightness, opacity: alpha) 
    }
    
    init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat = 1.0) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
        self.alpha = alpha
    }
    
    init(from color: Color) {
        // Convert Color to HSB - this is a simplified approach
        // In production, you might want more precise color space conversion
        let uiColor = UIColor(color)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        self.hue = h
        self.saturation = s
        self.brightness = b
        self.alpha = a
    }
}

internal enum PanelMetrics {
    static let height: CGFloat = 110
    static let cornerRadius: CGFloat = 10
    static let tileSize: CGFloat = 50
    static let spacing: CGFloat = 10
}

// MARK: - ColorPickerComponent Implementation

private extension ColorEditorControl {
    
    var previewView: some View {
        Group {
            if stops.count == 1 {
                RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                    .fill(stops[0].color)
            } else {
                let gradient = LinearGradient(
                    colors: stops.map(\.color),
                    startPoint: .top,
                    endPoint: .bottom
                )
                RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                    .fill(gradient)
            }
        }
    }
    
    var previewBorder: some View {
        RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
            .strokeBorder(.quaternary, lineWidth: 1)
    }
    
    var removeButton: some View {
        Button {
            if stops.count > 1 {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    stops.removeLast()
                    if selectedIndex >= stops.count { 
                        selectedIndex = max(0, stops.count - 1) 
                    }
                }
            }
        } label: {
            ColorPickerButton(
                systemName: "minus",
                isEnabled: stops.count > 1
            )
        }
        .buttonStyle(.plain)
        .disabled(stops.count <= 1)
    }
    
    var addButton: some View {
        Button {
            if stops.count < maxStops {
                let base = stops[selectedIndex]
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    stops.append(
                        GradientStop(
                            hue: base.hue,
                            saturation: base.saturation,
                            brightness: base.brightness
                        )
                    )
                    selectedIndex = stops.count - 1
                }
            }
        } label: {
            ColorPickerButton(
                systemName: "plus",
                isEnabled: stops.count < maxStops
            )
        }
        .buttonStyle(.plain)
        .disabled(stops.count >= maxStops)
    }
    
    var swatchRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                ColorSwatch(
                    stop: stop,
                    isSelected: index == selectedIndex,
                    isPressed: pressedSwatchIndex == index,
                    isBouncing: bouncingSwatchIndex == index,
                    onPress: { pressing in
                        withAnimation(.spring(response: 0.16, dampingFraction: 0.85)) {
                            pressedSwatchIndex = pressing ? index : nil
                        }
                    },
                    onTap: {
                        bouncingSwatchIndex = index
                        withAnimation(.spring(response: 0.14, dampingFraction: 0.65)) {}
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
                                bouncingSwatchIndex = nil
                            }
                        }
                        selectedIndex = index
                    }
                )
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: stops.count)
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: selectedIndex)
    }
    
    var panelContainer: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let panelSpacing: CGFloat = 80
            
            HStack(spacing: panelSpacing) {
                CustomPanelView(
                    hue: Binding(
                        get: { stops[selectedIndex].hue },
                        set: { stops[selectedIndex].hue = $0 }
                    ),
                    saturation: Binding(
                        get: { stops[selectedIndex].saturation },
                        set: { stops[selectedIndex].saturation = $0 }
                    ),
                    brightness: Binding(
                        get: { stops[selectedIndex].brightness },
                        set: { stops[selectedIndex].brightness = $0 }
                    ),
                    onBack: { 
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { 
                            mode = .presets 
                        } 
                    }
                )
                .frame(width: width, height: PanelMetrics.height)
                
                PresetsPanelView(
                    onShowCustom: { 
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { 
                            mode = .custom 
                        } 
                    },
                    onSelectSolid: { stop in
                        if selectedIndex < stops.count {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                stops[selectedIndex].hue = stop.hue
                                stops[selectedIndex].saturation = stop.saturation
                                stops[selectedIndex].brightness = stop.brightness
                                stops[selectedIndex].alpha = stop.alpha
                            }
                        }
                    },
                    onSelectGradient: { newStops in
                        let targetCount = newStops.count
                        let currentCount = stops.count
                        
                        if targetCount == currentCount {
                            // Same count - just update existing stops to avoid layout animation
                            withAnimation(.easeInOut(duration: 0.3)) {
                                for (index, newStop) in newStops.enumerated() {
                                    if index < stops.count {
                                        stops[index].hue = newStop.hue
                                        stops[index].saturation = newStop.saturation
                                        stops[index].brightness = newStop.brightness
                                        stops[index].alpha = newStop.alpha
                                    }
                                }
                            }
                            selectedIndex = 0
                        } else if targetCount > currentCount {
                            // Adding stops - preserve existing ones and add new ones
                            withAnimation(.easeInOut(duration: 0.3)) {
                                // Update existing stops
                                for (index, newStop) in newStops.prefix(currentCount).enumerated() {
                                    stops[index].hue = newStop.hue
                                    stops[index].saturation = newStop.saturation
                                    stops[index].brightness = newStop.brightness
                                    stops[index].alpha = newStop.alpha
                                }
                            }
                            // Add new stops with layout animation
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                                for newStop in newStops.suffix(targetCount - currentCount) {
                                    stops.append(newStop)
                                }
                            }
                            selectedIndex = 0
                        } else {
                            // Removing stops - preserve what we can and remove the rest
                            withAnimation(.easeInOut(duration: 0.3)) {
                                // Update remaining stops
                                for (index, newStop) in newStops.enumerated() {
                                    if index < stops.count {
                                        stops[index].hue = newStop.hue
                                        stops[index].saturation = newStop.saturation
                                        stops[index].brightness = newStop.brightness
                                        stops[index].alpha = newStop.alpha
                                    }
                                }
                            }
                            // Remove excess stops with layout animation
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                                stops.removeLast(currentCount - targetCount)
                            }
                            selectedIndex = 0
                        }
                    }
                )
                .frame(width: width, height: PanelMetrics.height)
            }
            .frame(width: width * 2 + panelSpacing, height: PanelMetrics.height, alignment: .leading)
            .offset(x: mode == .presets ? -(width + panelSpacing) : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: mode)
        }
        .frame(height: PanelMetrics.height)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Supporting Views

private struct ColorPickerButton: View {
    let systemName: String
    let isEnabled: Bool
    
    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(.primary.opacity(isEnabled ? 1 : 0.35))
        }
    }
}

private struct ColorSwatch: View {
    let stop: GradientStop
    let isSelected: Bool
    let isPressed: Bool
    let isBouncing: Bool
    let onPress: (Bool) -> Void
    let onTap: () -> Void
    
    var body: some View {
        let borderStyle: AnyShapeStyle = isSelected ? 
            AnyShapeStyle(.white) : 
            AnyShapeStyle(.tertiary)
        
        RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
            .fill(stop.color)
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
            .overlay(
                RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                    .inset(by: 0.5)
                    .strokeBorder(borderStyle, lineWidth: isSelected ? 3 : 1)
            )
            .transition(
                .asymmetric(
                    insertion: .collapseToZeroWidth(anchor: .leading).combined(with: .opacity),
                    removal: .collapseToZeroWidth(anchor: .trailing).combined(with: .opacity)
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
            .scaleEffect(isPressed || isBouncing ? 0.97 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.85, blendDuration: 0.1), value: isPressed)
            .animation(.spring(response: 0.22, dampingFraction: 0.75, blendDuration: 0.1), value: isBouncing)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: 44, pressing: onPress, perform: onTap)
            .simultaneousGesture(TapGesture().onEnded(onTap))
    }
}

// MARK: - Panel Views

private struct PresetsPanelView: View {
    let onShowCustom: () -> Void
    let onSelectSolid: (GradientStop) -> Void
    let onSelectGradient: ([GradientStop]) -> Void
    
    private let solidPresets: [GradientStop] = [
        GradientStop(hue: 0.0, saturation: 0.0, brightness: 1.0),      // White
        GradientStop(hue: 0.0, saturation: 0.0, brightness: 0.1),      // Black
        GradientStop(hue: 0.0, saturation: 0.9, brightness: 0.95),     // Red
        GradientStop(hue: 0.08, saturation: 0.9, brightness: 0.95),    // Orange
        GradientStop(hue: 0.14, saturation: 0.9, brightness: 0.95),    // Yellow
        GradientStop(hue: 0.34, saturation: 0.8, brightness: 0.9),     // Green
        GradientStop(hue: 0.48, saturation: 0.7, brightness: 0.9),     // Teal
        GradientStop(hue: 0.60, saturation: 0.75, brightness: 0.85),   // Blue
        GradientStop(hue: 0.75, saturation: 0.7, brightness: 0.9),     // Purple
        GradientStop(hue: 0.9, saturation: 0.7, brightness: 0.95)      // Pink
    ]
    
    private let gradientPresets: [[GradientStop]] = [
        // Sky: blue-white
        [
            GradientStop(hue: 0.6, saturation: 0.75, brightness: 0.85),
            GradientStop(hue: 0.0, saturation: 0.0, brightness: 1.0)
        ],
        // Sunset: purple-orange
        [
            GradientStop(hue: 0.75, saturation: 0.7, brightness: 0.9),
            GradientStop(hue: 0.08, saturation: 0.9, brightness: 0.95)
        ],
        // Mint: teal-green
        [
            GradientStop(hue: 0.48, saturation: 0.7, brightness: 0.9),
            GradientStop(hue: 0.34, saturation: 0.8, brightness: 0.9)
        ],
        // Fire: red-orange
        [
            GradientStop(hue: 0.0, saturation: 0.9, brightness: 0.95),
            GradientStop(hue: 0.08, saturation: 0.9, brightness: 0.95)
        ],
        // Sunrise: pink-yellow
        [
            GradientStop(hue: 0.9, saturation: 0.7, brightness: 0.95),
            GradientStop(hue: 0.14, saturation: 0.9, brightness: 0.95)
        ],
        // Ocean: deep blue-cyan
        [
            GradientStop(hue: 0.60, saturation: 0.75, brightness: 0.85),
            GradientStop(hue: 0.48, saturation: 0.7, brightness: 0.9)
        ],
        // Lavender: violet-pink
        [
            GradientStop(hue: 0.75, saturation: 0.7, brightness: 0.9),
            GradientStop(hue: 0.9, saturation: 0.7, brightness: 0.95)
        ],
        // Mango: yellow-orange-red
        [
            GradientStop(hue: 0.14, saturation: 0.9, brightness: 0.95),
            GradientStop(hue: 0.08, saturation: 0.9, brightness: 0.95),
            GradientStop(hue: 0.0, saturation: 0.9, brightness: 0.95)
        ],
        // Aurora: green-purple
        [
            GradientStop(hue: 0.34, saturation: 0.8, brightness: 0.9),
            GradientStop(hue: 0.75, saturation: 0.7, brightness: 0.9)
        ],
        // Candy: magenta-cyan
        [
            GradientStop(hue: 0.9, saturation: 0.7, brightness: 0.95),
            GradientStop(hue: 0.48, saturation: 0.7, brightness: 0.9)
        ]
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PanelMetrics.spacing) {
                // Custom button
                Button(action: onShowCustom) {
                    RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                        .fill(Color(white: 0.2))
                        .overlay(
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                                .strokeBorder(.tertiary, lineWidth: 1)
                        )
                        .frame(width: PanelMetrics.tileSize, height: PanelMetrics.height)
                        .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius))
                }
                .buttonStyle(.plain)
                
                // Preset grid
                VStack(spacing: PanelMetrics.spacing) {
                    // Solid colors
                    HStack(spacing: PanelMetrics.spacing) {
                        ForEach(Array(solidPresets.enumerated()), id: \.offset) { _, stop in
                            PresetTileView(stops: [stop]) {
                                onSelectSolid(stop)
                            }
                        }
                    }
                    // Gradients
                    HStack(spacing: PanelMetrics.spacing) {
                        ForEach(Array(gradientPresets.enumerated()), id: \.offset) { _, stops in
                            PresetTileView(stops: stops) {
                                onSelectGradient(stops)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, PanelMetrics.spacing)
            .contentMargins(.horizontal, PanelMetrics.spacing, for: .scrollContent)
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct PresetTileView: View {
    let stops: [GradientStop]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                .fill(stops.shapeStyle)
                .overlay(
                    RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(.tertiary, lineWidth: 1)
                )
                .frame(width: PanelMetrics.tileSize, height: PanelMetrics.tileSize)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extensions

private extension Array where Element == GradientStop {
    var shapeStyle: AnyShapeStyle {
        if count == 1 {
            return AnyShapeStyle(self[0].color)
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: self.map { $0.color },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

// MARK: - Transition Extensions

private struct CollapseToZeroWidth: ViewModifier {
    var isCollapsed: Bool
    var anchor: UnitPoint = .leading
    
    func body(content: Content) -> some View {
        content
            .frame(width: isCollapsed ? 0 : nil, alignment: alignment(from: anchor))
    }
    
    private func alignment(from anchor: UnitPoint) -> Alignment {
        switch anchor {
        case .leading: return .leading
        case .trailing: return .trailing
        case .center: return .center
        default: return .leading
        }
    }
}

private extension AnyTransition {
    static func collapseToZeroWidth(anchor: UnitPoint = .leading) -> AnyTransition {
        .modifier(
            active: CollapseToZeroWidth(isCollapsed: true, anchor: anchor),
            identity: CollapseToZeroWidth(isCollapsed: false, anchor: anchor)
        )
    }
}

#Preview {
    
    @Previewable
    @State
    var selectedColors: [Color] = [
        Color(hue: 0.6, saturation: 0.7, brightness: 0.9)
    ]
    
    ColorEditorControl(colors: $selectedColors)
}
