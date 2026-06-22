//
//  ChatReceiptCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// A trailing "Delivered" / "Read 3:42 PM" line under the user's latest sent message. Dumb — it
/// renders the already-formatted string it's handed.
public final class ChatReceiptCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatReceiptCell"

    private let label = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .default(size: 12, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.5)
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 12),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(text: String) {
        label.text = text
    }
}
#endif
