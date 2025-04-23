//
//  CodeView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct CodeView: View {
    
    public var data: Data
    
    public init(data: Data) {
        self.data = data
    }
    
    public var body: some View {
        ZStack {
            CodeShape(data: data)
            Circle()
                .mask(
                    ZStack {
                        Circle()
                            .fill(Color.white)
                        Image.asset(.flipcashLogo)
                            .renderingMode(.template)
                            .interpolation(.high)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(0.6)
//                            .font(.default(size: 150))
                            .foregroundColor(.black)
                            .padding(.leading, 6)
                    }
                    .compositingGroup()
                    .luminanceToAlpha()
                )
                .scaleEffect(KikCode.innerRingRatio)
        }
//        .drawingGroup()
        .scaledToFit()
    }
}

// MARK: - Code Shape -

struct CodeShape: Shape {
    
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    func path(in rect: CGRect) -> Path {
        do {
            var path = Path()
            let description = try KikCode.generateDescription(size: rect.size, payload: KikCode.Payload(data))
            
            let t = CGAffineTransform(
                translationX: (rect.size.width - description.size.width) * 0.5,
                y: (rect.size.height - description.size.height) * 0.5
            )
            
            for dot in description.dots {
                path.addPath(Path(dot.cgPath))
            }
            
            let strokeStyle = StrokeStyle(lineWidth: description.dotDimension)
            for arc in description.arcs {
                path.addPath(Path(arc.cgPath).strokedPath(strokeStyle))
            }
            
            return path.applying(t)
            
        } catch {
            print("Error rendering code: \(error)")
            return Path()
        }
    }
}

// MARK: - Previews -

struct CodeView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            CodeView(data: .placeholder35)
                .padding(0)
        }
        .previewLayout(.fixed(width: 300, height: 300))
    }
}

#endif
