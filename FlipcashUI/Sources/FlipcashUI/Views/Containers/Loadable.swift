//
//  Loadable.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct Loadable<T>: View where T: View {
    
    public let isLoading: Bool
    public let hideContent: Bool
    public let color: Color
    public let content: () -> T
    
    // MARK: - Init -
    
    public init(isLoading: Bool, hideContent: Bool = false, color: Color, @ViewBuilder content: @escaping () -> T) {
        self.isLoading = isLoading
        self.hideContent = hideContent
        self.color = color
        self.content = content
    }
    
    // MARK: - Body -
    
    public var body: some View {
        ZStack {
            LoadingView(color: .textSecondary)
                .if(!isLoading) { $0
                    .hidden()
                }
            content()
                .if(isLoading || hideContent) { $0
                    .hidden()
                }
        }
    }
}

#endif
