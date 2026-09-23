//
//  ChatUnreadDividerCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import SwiftUI
import UIKit
import FlipcashCore

/// The full-width "N Unread Messages" band above the first message the viewer had not read.
public final class ChatUnreadDividerCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatUnreadDividerCell"

    private let band = UIView()
    private let label = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        // Android's `divider` token, white at 10%.
        band.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        band.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(band)

        label.font = .default(size: 12, weight: .bold)
        label.textColor = UIColor(Color.textSecondary)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        band.addSubview(label)

        NSLayoutConstraint.activate([
            band.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            band.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            band.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            band.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            label.topAnchor.constraint(equalTo: band.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: band.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: band.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: band.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(count: Int) {
        label.text = ChatItem.unreadDividerText(count: count)
    }
}
#endif
