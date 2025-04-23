//
//  ToastContainer.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct ToastContainer<Content>: View where Content: View {
    
    private let toast: String?
    private let content: () -> Content
    
    // MARK: - Init -
    
    public init(toast: String?, @ViewBuilder content: @escaping () -> Content) {
        self.toast = toast
        self.content = content
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack {
                if let toast = toast {
                    BlurView {
                        Text(toast)
                            .padding([.leading, .trailing], 10)
                            .padding([.top, .bottom], 6)
                            .foregroundColor(.textMain)
                            .font(.appTextSmall)
                            .fixedSize()
                    }
                    .cornerRadius(100)
                    .transition(
                        .offset(x: 0, y: 20)
                        .combined(with: .opacity.animation(.easeOutFastest))
                    )
                }
            }
            .animation(.springFaster, value: toast)
            .frame(width: 1, alignment: .center)
            content()
        }
    }
}

// MARK: - Previews -

struct ToastContainer_Previews: PreviewProvider {
    static var previews: some View {
        ToastContainer(toast: "+$3.00") {
            Rectangle()
                .frame(width: 44, height: 44)
        }
        .previewLayout(.fixed(width: 300, height: 300))
    }
}

#endif
