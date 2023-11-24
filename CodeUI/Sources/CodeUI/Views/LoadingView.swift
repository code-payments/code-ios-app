//
//  LoadingView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct LoadingView: View, UIViewRepresentable {
    
    private var color: UIColor
    private var style: UIActivityIndicatorView.Style
    
    public init(color: Color = .black, style: UIActivityIndicatorView.Style = .medium) {
        self.color = UIColor(color)
        self.style = style
    }
    
    public func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: style)
        view.color = color
        updateUIView(view, context: context)
        return view
    }
    
    public func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {
        uiView.startAnimating()
    }
}

// MARK: - Previews -

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            LoadingView()
        }
        .previewLayout(.fixed(width: 200.0, height: 100.0))
    }
}

#endif
