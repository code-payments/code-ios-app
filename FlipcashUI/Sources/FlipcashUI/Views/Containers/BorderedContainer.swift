//
//  BorderedContainer.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct BorderedContainer<T>: View where T: View {
    
    public let content: () -> T
    
    // MARK: - Init -
    
    public init(@ViewBuilder content: @escaping () -> T) {
        self.content = content
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Metrics.buttonRadius * 2)
                .strokeBorder(Metrics.inputFieldStrokeColor(highlighted: false), lineWidth: Metrics.inputFieldBorderWidth(highlighted: false))
                .background(
                    Color.backgroundRow
                        .cornerRadius(Metrics.buttonRadius * 2)
                )
        )
    }
}
