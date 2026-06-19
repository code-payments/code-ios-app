//
//  ChatDateSeparatorCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// A centered day + time header between runs of messages (e.g. "Today 12:13 PM"). Dumb — it
/// renders the already-formatted string it's handed.
public final class ChatDateSeparatorCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatDateSeparatorCell"

    private let label = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .default(size: 12, weight: .bold) // .appTextHeading
        label.textColor = UIColor.white.withAlphaComponent(0.5) // secondaryText
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(text: String) {
        label.text = text
    }
}
#endif
