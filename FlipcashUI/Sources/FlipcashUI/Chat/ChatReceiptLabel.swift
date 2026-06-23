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

    public override init(frame: CGRect) {
        super.init(frame: frame)
        font = .default(size: 12, weight: .medium)
        textColor = UIColor.white.withAlphaComponent(0.5)
        textAlignment = .right
        numberOfLines = 1
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#endif
