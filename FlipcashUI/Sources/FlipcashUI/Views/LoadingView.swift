//
//  LoadingView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct LoadingView: View {

    private var color: Color
    private var style: UIActivityIndicatorView.Style

    public init(color: Color = .black, style: UIActivityIndicatorView.Style = .medium) {
        self.color = color
        self.style = style
    }

    public var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(style == .large ? .large : .regular)
            .tint(color)
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
