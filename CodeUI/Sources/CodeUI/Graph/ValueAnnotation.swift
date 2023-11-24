//
//  ValueAnnotation.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

struct ValueAnnotation: View {
    
    let text: String
    let normalizedValue: Double
    let geometry: GeometryProxy
    let positionBelow: Bool
    
    private let verticalOffset: CGFloat = 12.0
    
    // MARK: - Init -
    
    init(text: String, normalizedValue: Double, geometry: GeometryProxy, positionBelow: Bool) {
        self.text = text
        self.normalizedValue = normalizedValue
        self.geometry = geometry
        self.positionBelow = positionBelow
    }
    
    // MARK: - Body -
    
    var body: some View {
        Text(text)
            .padding([.leading, .trailing], 8)
            .padding([.top, .bottom], 3)
            .font(.appTextSmall)
            .background(Color.backgroundAction)
            .foregroundColor(.textAction)
            .cornerRadius(999)
            .offset(y: offsetY())
            .animation(.springFaster)
    }
    
    private func offsetY() -> CGFloat {
        let height = geometry.size.height
        let offset = height - (
            CGFloat(normalizedValue) * height
        ) -
        (height * 0.5) +
        (positionBelow ? verticalOffset : -verticalOffset)
        
        return min(max(offset, height * -0.5), (height * 0.5) - 25.0) // 25.0 is the height of the annotation
    }
}
