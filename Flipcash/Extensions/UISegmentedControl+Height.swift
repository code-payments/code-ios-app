//
//  UISegmentedControl+Height.swift
//  Flipcash
//

import UIKit

extension UISegmentedControl {
    override open func didMoveToSuperview() {
        super.didMoveToSuperview()
        setContentHuggingPriority(.defaultLow, for: .vertical)
    }
}
