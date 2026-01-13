//
//  Color.swift
//  Code
//
//  Created by Raul Riera on 2026-01-12.
//

import SwiftUI
import UIKit

extension Color {
    @available(iOS, introduced: 13.0, deprecated: 18.0, message: "Use the built-in mix(with:by:in:) function instead.")
	/// Backport of Color.mix(with:by:in:) for iOS versions prior to 18; defers to system when available
	public func mixed(with rhs: Color, by fraction: Double, in colorSpace: Gradient.ColorSpace = .perceptual) -> Color {
		if #available(iOS 18, *) {
			return self.mix(with: rhs, by: fraction, in: colorSpace)
		}
		let amount = fraction.clamped(to: 0...1)
        let rgbSpace: RGBColorSpace = .displayP3
		guard
			let lhs = UIColor(self).rgbaComponents,
			let rhs = UIColor(rhs).rgbaComponents
		else {
			return self
		}
		let r = lhs.r + (rhs.r - lhs.r) * amount
		let g = lhs.g + (rhs.g - lhs.g) * amount
		let b = lhs.b + (rhs.b - lhs.b) * amount
		let a = lhs.a + (rhs.a - lhs.a) * amount
		return Color(rgbSpace, red: r, green: g, blue: b, opacity: a)
	}
}

private extension Double {
	func clamped(to range: ClosedRange<Double>) -> Double {
		min(max(self, range.lowerBound), range.upperBound)
	}
}

private extension UIColor {
	var rgbaComponents: (r: Double, g: Double, b: Double, a: Double)? {
		var r: CGFloat = 0
		var g: CGFloat = 0
		var b: CGFloat = 0
		var a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
		return (Double(r), Double(g), Double(b), Double(a))
	}
}
