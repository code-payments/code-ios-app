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

/// The "N Unread Messages" caption between two hairlines, above the first message the viewer had
/// not read.
public final class ChatUnreadDividerCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatUnreadDividerCell"

    private let label = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .default(size: 12)
        label.textColor = UIColor(Color.textSecondary)
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let leading = Self.hairline()
        let trailing = Self.hairline()
        let row = UIStackView(arrangedSubviews: [leading, label, trailing])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            leading.widthAnchor.constraint(equalTo: trailing.widthAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(count: Int) {
        label.text = ChatItem.unreadDividerText(count: count)
    }

    /// Android's `divider` token, white at 10%, 1pt tall as `HorizontalDivider` draws it.
    private static func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        line.heightAnchor.constraint(equalToConstant: 1 / UITraitCollection.current.displayScale).isActive = true
        return line
    }
}
#endif
