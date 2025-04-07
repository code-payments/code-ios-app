//
//  RequestBillView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI
import FlipcashCore

public struct RequestBillView: View {
    
    public let currency: CurrencyCode
    public let text: String
    public let data: Data
    public let canvasSize: CGSize
    public let billSize: CGSize
    
    // MARK: - Init -
    
    /// Initialize a request view. Smaller
    /// means the bill will appear more square
    ///
    public init(currency: CurrencyCode, text: String, data: Data, canvasSize: CGSize, aspectRatio: CGFloat = 0.68) {
        self.currency   = currency
        self.text       = text
        self.data       = data
        self.canvasSize = canvasSize
        self.billSize   = Self.size(fitting: canvasSize, aspectRatio: aspectRatio)
    }
    
    private static func size(fitting size: CGSize, aspectRatio: CGFloat) -> CGSize {
        if size.height > size.width {
            var width  = size.width
            var height = round(width / aspectRatio)
            
            if height > size.height {
                width  = round(size.height * aspectRatio)
                height = size.height
            }
            
            let newSize = CGSize(
                width: width,
                height: height
            )
//            print("Calculated new size: \(newSize), from: \(size)")
            return newSize
            
        } else {
            var height = size.height
            var width  = round(height * aspectRatio)
            
            if width > size.width {
                width  = size.width
                height = round(size.width / aspectRatio)
            }
            
            let newSize = CGSize(
                width: width,
                height: height
            )
//            print("Calculated new size: \(newSize), from: \(size)")
            return newSize
        }
    }
    
    // MARK: - Body -
    
    private let triangleSize = CGSize(width: 8, height: 4)
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                
                // Background
                VStack(spacing: 0) {
                    TriangleStrip(size: triangleSize, color: .white)
                    Rectangle()
                        .fill(Color.white)
                    TriangleStrip(size: triangleSize, color: .white, reverse: true)
                }
                
                // Scan code
                VStack(spacing: 0) {
                    
                    Spacer()
                    
                    CodeView(data: data)
                        .foregroundColor(.textMain)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.codeWidth)
                        .padding(geometry.codePadding)
                        .background(
                            Circle()
                                .fill(Color.receiptGray)
                        )
                    
                    Spacer()
                    
                    // Separators
                    VStack(spacing: 3) {
                        separator()
                        separator()
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Bottom
                    CurrencyText(currency: currency, text: text)
                        .foregroundColor(.receiptGray)
                        .font(.appReceiptMedium)
                    
                    Spacer()
                }
            }
        }
        .frame(width: billSize.width, height: billSize.height)
        .drawingGroup(opaque: false, colorMode: .linear)
    }
    
    @ViewBuilder private func separator() -> some View {
        Line()
            .stroke(Color.dashedLine, style: .dashedLine)
            .frame(height: 1.0)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Line -

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path {
            $0.move(to: .zero)
            $0.addLine(to: CGPoint(x: rect.width, y: 0))
        }
    }
}

// MARK: - Triangles -

private struct TriangleStrip: View {
    
    let size: CGSize
    let color: Color
    let reverse: Bool
    
    init(size: CGSize, color: Color, reverse: Bool = false) {
        self.size = size
        self.color = color
        self.reverse = reverse
    }
    
    var body: some View {
        TriangleShape(
            size: size,
            reverse: reverse
        )
        .fill(color)
        .frame(height: size.height)
        .frame(maxWidth: .infinity)
    }
}

private struct TriangleShape: Shape {
    
    let size: CGSize
    let reverse: Bool
    
    init(size: CGSize, reverse: Bool = false) {
        self.size = size
        self.reverse = reverse
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let count = Int(rect.width / size.width) + 1
        for i in 0..<count {
            let offset = CGFloat(i) * size.width
            let transform = CGAffineTransform(translationX: offset, y: 0)
            path.addPath(.triangle(size: size), transform: transform)
        }
        
        if reverse {
            let p = UIBezierPath(cgPath: path.cgPath)
            let container = UIBezierPath(rect: rect)
            container.usesEvenOddFillRule = true
            container.append(p)
            return Path(container.cgPath)
        } else {
            return path
        }
    }
}

extension Path {
    static func triangle(size: CGSize) -> Path {
        Path {
            $0.move(to: CGPoint(x: size.width * 0.5, y: 0))
            $0.addLine(to: CGPoint(x: 0, y: size.height))
            $0.addLine(to: CGPoint(x: size.width, y: size.height))
            $0.closeSubpath()
        }
    }
}

// MARK: - GeometryProxy -

private extension GeometryProxy {
    
    var brandWidth: CGFloat {
        ceil(size.width * 0.18)
    }
    
    var valuePadding: CGFloat {
        ceil(size.width * 0.028)
    }
    
    var halfSize: CGSize {
        CGSize(width: size.width * 0.5, height: size.height * 0.5)
    }
    
    var codeWidth: CGFloat {
        ceil(size.width * 0.6)
    }
    
    var codePadding: CGFloat {
        ceil(size.width * 0.02)
    }
}

private extension Color {
    static let dashedLine = Color(hue: 0, saturation: 0, brightness: 0.35)
}

private extension StrokeStyle {
    static let dashedLine = StrokeStyle(
        lineWidth: 1.0,
        lineCap: .square,
        lineJoin: .miter,
        miterLimit: 0.0,
        dash: [3, 3],
        dashPhase: 0
    )
}

// MARK: - Previews -

struct RequestBillView_Previews: PreviewProvider {
    
    private static let sizes: [CGSize] = [
        CGSize(width: 414, height: 896), // iPhone 11 Pro Max
        CGSize(width: 375, height: 667), // iPhone 7
        CGSize(width: 320, height: 568), // iPhone SE
    ]
    
    static var previews: some View {
        Group {
            ForEach(sizes, id: \.width) { size in
                Background(color: .green) {
                    RequestBillView(
                        currency: .gbp,
                        text: "$5.00 of Kin",
                        data: .placeholder35,
                        canvasSize: size
                    )
                }
                .previewLayout(.fixed(width: size.width, height: size.height))
            }
        }
    }
}

#endif
