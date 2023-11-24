//
//  ViewReader.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct ViewReader<T>: UIViewRepresentable where T: UIView {
    
    public var configuration: (T) -> Void
    
    public init(_ type: T.Type, configuration: @escaping (T) -> Void) {
        self.configuration = configuration
    }
    
    public func makeUIView(context: Context) -> some UIView {
        let view = DummyView()
        
        return view
    }
    
    public func updateUIView(_ uiView: UIViewType, context: Context) {
        if let view = uiView.findSuperview(type: T.self) {
            configuration(view)
        }
    }
}

private class DummyView: UIView {
    override var intrinsicContentSize: CGSize {
        .zero
    }
}

// MARK: - View Search -

private extension UIView {
    func findSuperview<T>(type: T.Type) -> T? {
        if let superview = superview {
            if let foundView = superview as? T {
                return foundView
            } else {
                return superview.findSuperview(type: T.self)
            }
        }
        return nil
    }
}

#endif
