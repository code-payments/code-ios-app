//
//  BillView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI
import FlipcashCore

public struct BillView: View {
    
    public let fiat: Fiat
    public let data: Data
    public let canvasSize: CGSize
    public let billSize: CGSize
    public let action: VoidAction
    
    public let string: String
    
    // MARK: - Init -
    
    /// Initialize a bill view. Aspect ratios of various bills. Smaller
    /// means the bill will appear more square
    ///
    /// US Dollar: 0.425
    /// Euro:      0.510
    /// Code:      0.555
    ///
    public init(fiat: Fiat, data: Data, canvasSize: CGSize, aspectRatio: CGFloat = 0.555, action: VoidAction? = nil) {
        self.fiat       = fiat
        self.data       = data
        self.canvasSize = canvasSize
        self.action     = action ?? {}
        self.string     = fiat.formatted(suffix: nil)
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
    
    let billColor = Color(r: 0, g: 70, b: 2)
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack {
                    
                    Rectangle()
                        .fill(billColor.opacity(0.65))
                    
                    // More opaque layer for the code
                    // to help with scanning
                    Circle()
                        .fill(Color.black.opacity(0.5))
                    
                    // Main background (clip)
                    geometry.clipShape(fill: billColor)
                    
                    // Security strip
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            Image.asset(.securityStrip)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: geometry.securityStripSize.width, height: geometry.securityStripSize.height)
                    .position(x: geometry.securityStripPosition.x, y: geometry.securityStripPosition.y)
                    
                    ZStack {
                        // Hexagons
                        Image.asset(.hexagons)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width)
                            .position(x: geometry.hexagonsPosition.x, y: geometry.hexagonsPosition.y)
                            .blendMode(.multiply)
                            .opacity(0.6)
                            .mask(geometry.clipShape(fill: .white))
                        
                        // Grid pattern
                        Image.asset(.grid)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.gridWidth)
                            .position(x: geometry.gridPosition.x, y: geometry.gridPosition.y)
                            .mask(geometry.clipShape(fill: .white))
                            .opacity(0.5)
                        
                        // Globe
                        Image.asset(.globe)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.globeWidth)
                            .position(x: geometry.globePosition.x, y: geometry.globePosition.y)
                            .mask(geometry.clipShape(fill: .white))
                        
                        Image.asset(.waves)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .rotationEffect(.degrees(0))
                            .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.9)
                            .mask(geometry.clipShape(fill: .white))
                    }
                    
                    // Bill Value Top Left
                    VerticalContainer(angle: .degrees(270)) {
                        VStack {
                            HStack {
                                Spacer()
                                Text(string)
                                    .lineLimit(1)
                                    .foregroundColor(.textMain)
                                    .font(geometry.valueFont)
                                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 2, y: 2)
                                    .padding(.trailing, geometry.topStripHeight + geometry.securityStripSize.height * 0.5)
                                    .padding(.top, geometry.valuePadding)
                            }
                            Spacer()
                        }
                    }
                    
                    
                    // Bill Value Bottom Right
                    VerticalContainer(angle: .degrees(270)) {
                        VStack {
                            Spacer()
                            HStack {
                                Text(string)
                                    .lineLimit(1)
                                    .foregroundColor(.textMain)
                                    .font(geometry.valueFont)
                                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 2, y: 2)
                                    .padding(.leading, geometry.topStripHeight + geometry.securityStripSize.height * 0.5)
                                    .padding(.bottom, geometry.valuePadding)
                                Spacer()
                            }
                        }
                    }
                    
                    // Lines
                    VStack {
                        HStack {
                            // September
                            LineView(count: 9, spacing: geometry.linesSpacing)
                            
                            Spacer()
                            
                            // Sept 12
                            LineView(count: 12, spacing: geometry.linesSpacing)
                        }
                        .frame(height: geometry.linesHeight)
                        
                        Spacer()
                        
                        HStack {
                            // Mint
                            Text(Mint.usdc.base58)
                                .foregroundColor(.textMain.opacity(0.2))
                                .font(geometry.mintFont)
                            Spacer()
                        }
                        .padding(.bottom, geometry.mintPadding)
                        
                        HStack {
                            VStack {
                                Image.asset(.flipcashBrand)
                                    .resizable()
                                    .renderingMode(.template)
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundColor(.textMain.opacity(0.2))
                                    .frame(width: geometry.brandWidth)
                                Spacer()
                            }
                            Spacer()
                            
                            // 2017
                            LineView(count: 17, spacing: geometry.linesSpacing)
                                .padding(.bottom, -2)
                        }
                        .frame(height: geometry.linesHeight)
                    }
                    .padding(.leading,  geometry.valuePadding)
                    .padding(.trailing, geometry.valuePadding * 2.0)
                }
                .clipped()
                
                // Scan code
                CodeView(data: data)
                    .foregroundColor(.textMain)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.codeWidth)
                    .position(x: geometry.halfSize.width, y: geometry.halfSize.height)
                    .shadow(color: Color.black.opacity(0.6), radius: 3, x: 0, y: 2)
            }
        }
        .frame(width: billSize.width, height: billSize.height)
        .drawingGroup(opaque: false, colorMode: .linear)
    }
}

struct LineView: View {
    
    let count: Int
    let spacing: CGFloat
    
    // MARK: - Init -
    
    init(count: Int, spacing: CGFloat) {
        self.count = count
        self.spacing = spacing
    }
    
    // MARK: - Body -
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { _ in
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1)
                    .rotationEffect(.degrees(-18), anchor: .top)
            }
        }
    }
}

// MARK: - BillClipShape -

private struct BillClipShape: Shape {
    
    let codeWidth: CGFloat
    let codePadding: CGFloat
    let topPadding: CGFloat
    let securityStripHeight: CGFloat
    
    // MARK: - Init -
    
    init(codeWidth: CGFloat, codePadding: CGFloat, topPadding: CGFloat, securityStripHeight: CGFloat) {
        self.codeWidth = codeWidth
        self.codePadding = codePadding
        self.topPadding = topPadding
        self.securityStripHeight = securityStripHeight
    }
    
    // MARK: - Path -
    
    func path(in rect: CGRect) -> Path {
        let securityRect = CGRect(
            x: 0,
            y: topPadding,
            width: rect.width,
            height: securityStripHeight
        )
        
        let codeRect = CGRect(
            x: (rect.width  - codeWidth) * 0.5,
            y: (rect.height - codeWidth) * 0.5,
            width: codeWidth,
            height: codeWidth
        )
        .insetBy(dx: -codePadding, dy: -codePadding)
        
        var containerPath = Path()
        containerPath.addRect(rect)
        containerPath.addRect(securityRect)
        containerPath.addEllipse(in: codeRect)
        return containerPath
    }
}

// MARK: - GeometryProxy -

private extension GeometryProxy {
    
    var valueFont: Font {
        .default(size: ceil(size.width * 0.12), weight: .bold)
    }
    
    var mintFont: Font {
        .default(size: ceil(size.width * 0.024), weight: .regular)
    }
    
    var brandWidth: CGFloat {
        ceil(size.width * 0.18)
    }
    
    var mintPadding: CGFloat {
        ceil(size.height * 0.01)
    }
    
    var valuePadding: CGFloat {
        ceil(size.width * 0.025)
    }
    
    var halfSize: CGSize {
        CGSize(width: size.width * 0.5, height: size.height * 0.5)
    }
    
    var linesHeight: CGFloat {
        topStripHeight - 2
    }
    
    var linesSpacing: CGFloat {
        ceil(size.width * 0.032)
    }
    
    var codeWidth: CGFloat {
        ceil(size.width * 0.6)
    }
    
    var codePadding: CGFloat {
        ceil(size.width * 0.02)
    }
    
    var globeWidth: CGFloat {
        ceil(size.width * 1.45)
    }
    
    var gridWidth: CGFloat {
        ceil(size.width * 1.75)
    }
    
    var topStripHeight: CGFloat {
        ceil(size.height * 0.05)
    }
    
    var securityStripSize: CGSize {
        CGSize(
            width: size.width,
            height: ceil(size.height * 0.063)
        )
    }
    
    var securityStripPosition: CGPoint {
        CGPoint(
            x: size.width * 0.5,
            y: topStripHeight + (securityStripSize.height * 0.5)
        )
    }
    
    var globePosition: CGPoint {
        CGPoint(
            x: size.width * 0.26,
            y: size.height * 0.65
        )
    }
    
    var gridPosition: CGPoint {
        CGPoint(
            x: size.width * 0.5,
            y: size.height * 0.35
        )
    }
    
    var hexagonsPosition: CGPoint {
        CGPoint(
            x: size.width * 0.5,
            y: size.height * 0.5
        )
    }
    
    @ViewBuilder func clipShape(fill: Color) -> some View {
        BillClipShape(
            codeWidth: codeWidth,
            codePadding: codePadding,
            topPadding: topStripHeight,
            securityStripHeight: securityStripSize.height
        )
        .fill(fill, style: FillStyle(eoFill: true, antialiased: true))
    }
}

// MARK: - Previews -

struct BillView_Previews: PreviewProvider {
    
    private static let sizes: [CGSize] = [
        CGSize(width: 414, height: 896), // iPhone 11 Pro Max
        CGSize(width: 375, height: 667), // iPhone 7
        CGSize(width: 320, height: 568), // iPhone SE
    ]
    
    static var previews: some View {
        Group {
            ForEach(sizes, id: \.width) { size in
                BillView(fiat: 5_00, data: .placeholder35, canvasSize: size)
                    .previewLayout(.fixed(width: size.width, height: size.height))
            }
        }
    }
}

#endif
