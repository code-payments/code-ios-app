//
//  CodeView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SharedCoreKit
import SwiftUI

/// A scannable code: the data marks, with the Flipcash badge in the middle well.
///
/// Both halves come from `SharedCoreKit` — the same shared geometry and badge artwork the
/// exported SVG renders from and Android draws — so a code on screen, an exported one, and
/// the Android one are all the same figure.
public struct CodeView: View {
    
    public var data: Data
    
    public init(data: Data) {
        self.data = data
    }
    
    public var body: some View {
        ZStack {
            CodeFigure(data: data, part: .marks)
            // The badge is a disc with the glyph cut out of it. Filled non-zero the glyph
            // fills back in, leaving a plain white disc.
            CodeFigure(data: data, part: .badge)
                .fill(style: FillStyle(eoFill: true))
        }
        .scaledToFit()
    }
}

// MARK: - Code Figure -

/// One half of a code, laid out square and centred in whatever rect it is handed.
nonisolated struct CodeFigure: Shape {
    
    enum Part {
        case marks
        case badge
        
        /// Whether laying this part out needs the badge at all.
        var needsBadge: Bool {
            switch self {
            case .marks: false
            case .badge: true
            }
        }
    }
    
    let data: Data
    let part: Part
    
    func path(in rect: CGRect) -> Path {
        let dimension = min(rect.width, rect.height)
        
        // Only a payload that is empty or longer than the code can carry fails, and callers
        // pass one the server issued; drawing nothing is the honest result either way.
        guard let figure = try? KikCode.figure(
            payload: data,
            dimension: dimension,
            includeBadge: part.needsBadge
        ) else {
            return Path()
        }
        
        let cgPath: CGPath?
        switch part {
        case .marks: cgPath = figure.marks
        case .badge: cgPath = figure.badge
        }
        guard let cgPath else { return Path() }
        
        return Path(cgPath).applying(CGAffineTransform(
            translationX: rect.minX + (rect.width - dimension) * 0.5,
            y: rect.minY + (rect.height - dimension) * 0.5
        ))
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
