//
//  ChatReceiptLabel.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// The "Delivered" / "Read 3:42 PM" line under the user's latest sent bubble. A styled label the
/// message cell embeds below its content — not a standalone transcript row — so it sizes and
/// animates with its bubble instead of inserting and moving on its own.
public final class ChatReceiptLabel: UILabel {

    /// Keeps the line off the bubble's trailing edge so "Delivered" / "Read 3:42 PM" don't sit flush
    /// against the column's right side.
    private static let textInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 10)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        font = .default(size: 12, weight: .medium)
        textColor = UIColor.white.withAlphaComponent(0.5)
        textAlignment = .right
        numberOfLines = 1
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: Self.textInsets))
    }

    public override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        var rect = super.textRect(forBounds: bounds.inset(by: Self.textInsets), limitedToNumberOfLines: numberOfLines)
        rect.size.width += Self.textInsets.right
        return rect
    }
}
#endif
