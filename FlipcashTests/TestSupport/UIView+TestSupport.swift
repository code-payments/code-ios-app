//
//  UIView+TestSupport.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit

extension UIView {
    /// All descendants of the given type, depth-first.
    func descendants<T>(of type: T.Type) -> [T] {
        subviews.compactMap { $0 as? T } + subviews.flatMap { $0.descendants(of: type) }
    }
}
