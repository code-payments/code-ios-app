//
//  TwitterBillView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI
import FlipcashCore

public struct TwitterBillView: View {
    
    public let username: String
    public let data: Data
    public let canvasSize: CGSize
    public let billSize: CGSize
    
    // MARK: - Init -
    
    /// Initialize a login view. Smaller
    /// means the bill will appear more square
    ///
    public init(username: String, data: Data, canvasSize: CGSize, aspectRatio: CGFloat = 0.57) {
        self.username   = username
        self.data       = data
        self.canvasSize = canvasSize
        self.billSize   = Self.size(
            fitting: CGSize(
                width: canvasSize.width - 40,
                height: canvasSize.height - 40
            ),
            aspectRatio: aspectRatio
        )
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
            
            return newSize
        }
    }
    
    // MARK: - Body -
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                
                // Background
                ZStack {
                    Rectangle()
                        .fill(
                            EllipticalGradient(
                                gradient: Gradient(
                                    stops: [
                                        .init(color: .white.opacity(1.0),           location: 0),
                                        .init(color: .backgroundMain.opacity(0.44), location: 1)
                                    ]
                                ),
                                center: .topLeading,
                                startRadiusFraction: 0,
                                endRadiusFraction: 1.2
                            )
                            .opacity(0.15)
                        )
                        .blur(radius: geometry.size.width * 0.07)
                        .overlay( // Inner shadow
                            Rectangle()
                                .stroke(Color.backgroundMain.opacity(0.7), lineWidth: 30)
                                .blur(radius: 18)
                        )
                }
                .background(Color.backgroundMain)
                .overlay( // Subtle black 2px border
                    Rectangle()
                        .stroke(Color.backgroundMain.opacity(0.5), lineWidth: 2)
                        .blur(radius: 1)
                )
                
                // Scan code
                VStack(spacing: 0) {
                    
                    Spacer()
                    
                    CodeView(data: data)
                        .foregroundColor(.textMain)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.codeWidth)
                        .padding(geometry.codePadding)
                    
                    Spacer()
                    
                    HStack {
                        Image.asset(.twitter)
                            .padding(.top, 2)
                        Text(username)
                    }
                    .font(.appTextLarge)
                    .foregroundColor(.textMain)
                    
                    Spacer()
                }
                .shadow(color: .black.opacity(0.6), radius: 1.2, x: 0, y: 2)
            }
        }
        .frame(width: billSize.width, height: billSize.height)
        .drawingGroup(opaque: true, colorMode: .linear)
    }
}

// MARK: - GeometryProxy -

private extension GeometryProxy {
    
    var brandWidth: CGFloat {
        ceil(size.width * 0.18)
    }
    
    var codeWidth: CGFloat {
        ceil(size.width * 0.65)
    }
    
    var codePadding: CGFloat {
        ceil(size.width * 0.02)
    }
}

// MARK: - Previews -

struct TwitterBillView_Previews: PreviewProvider {
    
    private static let sizes: [CGSize] = [
        CGSize(width: 414, height: 896), // iPhone 11 Pro Max
        CGSize(width: 375, height: 667), // iPhone 7
        CGSize(width: 320, height: 568), // iPhone SE
    ]
    
    static var previews: some View {
        Group {
            ForEach(sizes, id: \.width) { size in
                Background(color: .green) {
                    TwitterBillView(
                        username: "GetCode",
                        data: .placeholder35,
                        canvasSize: CGSize(width: size.width - 40, height: size.height)
                    )
                }
                .previewLayout(.fixed(width: size.width, height: size.height))
            }
        }
    }
}

#endif
