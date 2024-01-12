//
//  LoginBillView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI
import CodeServices

public struct LoginBillView: View {
    
    public let data: Data
    public let canvasSize: CGSize
    public let billSize: CGSize
    
    // MARK: - Init -
    
    /// Initialize a login view. Smaller
    /// means the bill will appear more square
    ///
    public init(data: Data, canvasSize: CGSize, aspectRatio: CGFloat = 0.68) {
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
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                
                // Background
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(LinearGradient.loginBillBackground)
                }
                .cornerRadius(8)
                
                // Scan code
                VStack(spacing: 0) {
                    
                    Spacer()
                    
                    CodeView(data: data)
                        .foregroundColor(.textMain)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.codeWidth)
                        .padding(geometry.codePadding)
                    
                    Spacer()
                }
                
                // Brand
                VStack {
                    Spacer()
                    HStack {
                        Image.asset(.codeBrand)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.textMain.opacity(0.6))
                            .frame(width: geometry.brandWidth)
                        Spacer()
                    }
                }
                .padding(10)
            }
        }
        .frame(width: billSize.width, height: billSize.height)
        .drawingGroup(opaque: false, colorMode: .linear)
    }
}

// MARK: - GeometryProxy -

private extension GeometryProxy {
    
    var brandWidth: CGFloat {
        ceil(size.width * 0.18)
    }
    
    var codeWidth: CGFloat {
        ceil(size.width * 0.6)
    }
    
    var codePadding: CGFloat {
        ceil(size.width * 0.02)
    }
}

// MARK: - Previews -

struct LoginBillView_Previews: PreviewProvider {
    
    private static let sizes: [CGSize] = [
        CGSize(width: 414, height: 896), // iPhone 11 Pro Max
        CGSize(width: 375, height: 667), // iPhone 7
        CGSize(width: 320, height: 568), // iPhone SE
    ]
    
    static var previews: some View {
        Group {
            ForEach(sizes, id: \.width) { size in
                Background(color: .green) {
                    LoginBillView(
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
