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

    public let fiat: Quarks
    public let data: Data
    public let canvasSize: CGSize
    public let billSize: CGSize
    public let action: VoidAction
    public let backgroundColors: [Color]

    public let string: String

    // MARK: - Init -

    /// Initialize a bill view. Aspect ratios of various bills. Smaller
    /// means the bill will appear more square
    ///
    /// US Dollar: 0.425
    /// Euro:      0.510
    /// Code:      0.555
    ///
    public init(fiat: Quarks, data: Data, canvasSize: CGSize, aspectRatio: CGFloat = 0.555, backgroundColors: [Color]? = nil, mint: PublicKey? = nil, action: VoidAction? = nil) {
        self.fiat       = fiat
        self.data       = data
        self.canvasSize = canvasSize
        self.action     = action ?? {}
        self.string     = fiat.formatted(suffix: nil)
        self.billSize   = Self.size(fitting: canvasSize, aspectRatio: aspectRatio)

        // Use provided colors or get default colors based on mint
        self.backgroundColors = backgroundColors ?? Self.defaultColors(for: mint)
    }

    private static func defaultColors(for mint: PublicKey?) -> [Color] {
        let green = Color(r: 0, g: 70, b: 2)

        guard let mint = mint else {
            return [green]
        }

        // Custom bill colors for select
        // currencies that are know now
        switch mint {
        case .jeffy:
            return [
                Color(r: 120, g: 49,  b: 0),   // #783100
                Color(r: 238, g: 186, b: 127), // #EEBA7F
            ]

        case .bogey:
            return [
                Color(r: 0,   g: 77,  b: 15),  // #004D0F
                Color(r: 106, g: 136, b: 112), // #6A8870
                Color(r: 171, g: 231, b: 183), // #ABE7B7
            ]

        case .marketCoin:
            return [
                Color(r: 131, g: 94,  b: 51),  // #835E33
                Color(r: 210, g: 149, b: 79),  // #D2954F
                Color(r: 255, g: 213, b: 116), // #FFD574
            ]

        case .bits:
            return [
                Color(r: 9,   g: 51,  b: 114), // #093372
                Color(r: 62,  g: 112, b: 188), // #3E70BC
                Color(r: 172, g: 190, b: 221), // #ACBEDD
            ]

        case .float:
            return [
                Color(r: 187, g: 79,  b: 33),  // #BB4F21
                Color(r: 175, g: 159, b: 158), // #AF9F9E
                Color(r: 200, g: 137, b: 103), // #C88967
            ]

        case .xp:
            return [
                Color(r: 86,  g: 33,  b: 187), // #5621BB
                Color(r: 169, g: 155, b: 214), // #A99BD6
                Color(r: 78,  g: 170, b: 197), // #4EAAC5
            ]
        
        case .badBoys, .badBoysMock:
            return [
                Color(r: 44,  g: 44,  b: 44),  // #2C2C2C
                Color(r: 170, g: 170, b: 170), // #AAAAAA
            ]

        default:
            return [green]  // Default green
        }
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

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack {

                    // Background gradient or solid color
                    if backgroundColors.count == 1 {
                        Rectangle()
                            .fill(backgroundColors[0].opacity(0.65))
                    } else {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: backgroundColors.map { $0.opacity(0.65) },
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                    }

                    // More opaque layer for the code
                    // to help with scanning
                    Rectangle()
                        .fill(Color.black.opacity(0.5))

                    // Main background (clip)
                    if backgroundColors.count == 1 {
                        geometry.clipShape(fill: backgroundColors[0])
                    } else {
                        geometry.clipShape(gradient: backgroundColors)
                    }
                    
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
                            // October
                            LineView(count: 10, spacing: geometry.linesSpacing)
                            
                            Spacer()
                            
                            // Oct 31
                            LineView(count: 31, spacing: geometry.linesSpacing)
                        }
                        .frame(height: geometry.linesHeight)
                        
                        Spacer()
                        
                        HStack {
                            // Mint
                            Text(PublicKey.usdf.base58)
                                .foregroundColor(.textMain.opacity(0.2))
                                .font(geometry.mintFont)
                            Spacer()
                        }
                        .padding(.bottom, geometry.mintPadding)
                        
                        HStack(spacing: 0) {
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
                            
                            // 2 (of 2008)
                            LineView(count: 2, spacing: geometry.linesSpacing)
                                .padding(.bottom, -2)
                                .padding(.trailing, geometry.valuePadding * 4)
                            
                            // 2008
                            LineView(count: 8, spacing: geometry.linesSpacing)
                                .padding(.bottom, -2)
                                .padding(.trailing, geometry.valuePadding)
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
                    .aspectRatio(1.0, contentMode: .fit)
                    .frame(width: geometry.codeWidth, height: geometry.codeWidth)
                    .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.5)
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
                    .fill(Color.white.opacity(0.1))
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
        ceil(size.width * 0.016)
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

    @ViewBuilder func clipShape(gradient: [Color]) -> some View {
        BillClipShape(
            codeWidth: codeWidth,
            codePadding: codePadding,
            topPadding: topStripHeight,
            securityStripHeight: securityStripSize.height
        )
        .fill(
            LinearGradient(
                colors: gradient,
                startPoint: .bottom,
                endPoint: .top
            ),
            style: FillStyle(eoFill: true, antialiased: true)
        )
    }
}

/// Temporary hardcoded mint address to style bills. These will be removed by a server response in the future
private extension PublicKey {
    static let jeffy = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")
    static let xp = try! PublicKey(base58: "6oZnhB1FPrUaDfhRCVZnbVWNKVx9wgj84vKGH7eMpzXL")
    static let marketCoin = try! PublicKey(base58: "311m6Sb1814PfAxkEcqq6MNdBiVZLr8VWuAWDSC72euW")
    static let bits = try! PublicKey(base58: "A3e8dzb1y4gqGP2cnCS3UU8dm5YNrFpZBpjjdoZdtfnB")
    static let float = try! PublicKey(base58: "5APqK9YUZupKt7rRUrpYy6WV3RPuxA71ZtKJffDUMdPP")
    static let bogey = try! PublicKey(base58: "3AhBb1fpDTp1F9hPkZjRPDejXBM9S5vfpVdvn66vLYnT")
    static let badBoys = try! PublicKey(base58: "64dkhPKhdjc2xg3NLyDjC14wiXHLnGXHHUxJnqZVugJt")
    static let badBoysMock = try! PublicKey(base58: "2psDP3LAvbNzfvBYNMs9ieMpsD8PVzyQsKNfZrjEKoDN")
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
