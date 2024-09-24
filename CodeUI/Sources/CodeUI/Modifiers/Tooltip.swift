//
//  Tooltip.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Tooltip: ViewModifier {
    
    public let alignment: Alignment
    public let properties: Properties
    public let text: String
    
    @State private var size: CGSize = .zero
    
    public init(alignment: Alignment, properties: Properties, text: String) {
        self.alignment = alignment
        self.properties = properties
        self.text = text
    }

    public func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .overlay {
                    GeometryReader { g in
                        TooltipArrow(inverted: alignment.isArrowInverted)
                            .fill(properties.backgroundColor)
                            .frame(width: properties.arrowSize.width, height: properties.arrowSize.height)
                            .position(arrowPosition(g: g))
                        
                        TooltipContent(properties: properties, content: text)
                            .frame(maxWidth: properties.maxWidth)
                            .font(properties.textFont)
                            .foregroundColor(properties.textColor)
                            .multilineTextAlignment(properties.textAlignment)
                            .fixedSize()
                            .position(contentPosition(g: g))
                    }
                }
                .onPreferenceChange(OverlaySizePreferenceKey.self) { value in
                    size = value ?? .zero
                }
        }
    }
    
    private func arrowPosition(g: GeometryProxy) -> CGPoint {
        switch alignment {
        case .bottomLeading:
            CGPoint(
                x: g.size.width * 0.5 + properties.offset,
                y: g.size.height + (properties.arrowSize.height * 0.5) + properties.distance
            )
        case .bottomTrailing:
            CGPoint(
                x: g.size.width * 0.5 + properties.offset,
                y: g.size.height + (properties.arrowSize.height * 0.5) + properties.distance
            )
        case .topLeading:
            CGPoint(
                x: g.size.width * 0.5 + properties.offset,
                y: -properties.arrowSize.height * 0.5 - properties.distance
            )
        case .topTrailing:
            CGPoint(
                x: g.size.width * 0.5 + properties.offset,
                y: -properties.arrowSize.height * 0.5 - properties.distance
            )
        }
    }
    
    private func contentPosition(g: GeometryProxy) -> CGPoint {
        switch alignment {
        case .bottomLeading:
            CGPoint(
                x: size.width * 0.5 + properties.offset,
                y: size.height * 0.5 + g.size.height + properties.arrowSize.height + properties.distance
            )
        case .bottomTrailing:
            CGPoint(
                x: -size.width * 0.5 + g.size.width + properties.offset,
                y: size.height * 0.5 + g.size.height + properties.arrowSize.height + properties.distance
            )
        case .topLeading:
            CGPoint(
                x: size.width * 0.5 + properties.offset,
                y: -size.height * 0.5 - properties.arrowSize.height - properties.distance
            )
        case .topTrailing:
            CGPoint(
                x: -size.width * 0.5 + g.size.width + properties.offset,
                y: -size.height * 0.5 - properties.arrowSize.height - properties.distance
            )
        }
    }
}

extension Tooltip {
    public struct Properties: Sendable {
        
        public var arrowSize: CGSize
        public var cornerRadius: CGFloat
        public var maxWidth: CGFloat
        public var distance: CGFloat
        public var offset: CGFloat
        
        public var backgroundColor: Color
        
        public var textPadding: CGSize
        public var textFont: Font
        public var textAlignment: TextAlignment
        public var textColor: Color
        
        public init(
            arrowSize: CGSize = CGSize(width: 10, height: 4),
            cornerRadius: CGFloat = 8,
            maxWidth: CGFloat = 200,
            distance: CGFloat = 0,
            offset: CGFloat = 0,
            backgroundColor: Color = .blue,
            textPadding: CGSize = CGSize(width: 8, height: 8),
            textFont: Font = .body,
            textAlignment: TextAlignment = .leading,
            textColor: Color = .black
        ) {
            self.arrowSize = arrowSize
            self.cornerRadius = cornerRadius
            self.maxWidth = maxWidth
            self.distance = distance
            self.offset = offset
            
            self.backgroundColor = backgroundColor
            
            self.textPadding = textPadding
            self.textFont = textFont
            self.textAlignment = textAlignment
            self.textColor = textColor
        }
    }
}

extension Tooltip {
    public enum Alignment {
        case bottomLeading
        case bottomTrailing
        case topLeading
        case topTrailing
        
        fileprivate var isArrowInverted: Bool {
            switch self {
            case .bottomLeading, .bottomTrailing:
                return false
            case .topLeading, .topTrailing:
                return true
            }
        }
    }
}

extension View {
    public func tooltip(alignment: Tooltip.Alignment = .bottomLeading, properties: Tooltip.Properties, text: String) -> some View {
        self.modifier(
            Tooltip(
                alignment: alignment,
                properties: properties,
                text: text
            )
        )
    }
}

// MARK: - Private -

private struct TooltipContent: View {
    
    let properties: Tooltip.Properties
    let content: String
    
    init(properties: Tooltip.Properties, content: String) {
        self.properties = properties
        self.content = content
    }
    
    var body: some View {
        Text(content)
            .padding(.vertical, properties.textPadding.height)
            .padding(.horizontal, properties.textPadding.width)
            .background {
                RoundedRectangle(cornerRadius: properties.cornerRadius)
                    .fill(properties.backgroundColor)
            }
            .overlay {
                GeometryReader { g in
                    Color.clear
                        .preference(key: OverlaySizePreferenceKey.self, value: g.size)
                }
            }
    }
}

private struct TooltipArrow: Shape {
    
    let inverted: Bool
    
    init(inverted: Bool) {
        self.inverted = inverted
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(
            x: rect.midX,
            y: inverted ? rect.maxY : rect.minY
        ))
        
        path.addLine(to: CGPoint(
            x: rect.minX,
            y: inverted ? rect.minY : rect.maxY
        ))
        
        path.addLine(to: CGPoint(
            x: rect.maxX,
            y: inverted ? rect.minY : rect.maxY
        ))
        
        path.closeSubpath()
        return path
    }
}

private struct OverlaySizePreferenceKey: PreferenceKey {
    typealias Value = CGSize?

    static var defaultValue: Value = nil

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value = nextValue() ?? value
    }
}
