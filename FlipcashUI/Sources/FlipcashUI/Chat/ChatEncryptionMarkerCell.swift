//
//  ChatEncryptionMarkerCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

/// The centered "🔒 Encrypted ›" line where a DM's end-to-end-encrypted messages begin. Tapping it
/// calls `onTap`.
public final class ChatEncryptionMarkerCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatEncryptionMarkerCell"

    private let button = UIButton(type: .system)
    private var onTap: (() -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        button.setAttributedTitle(Self.title(), for: .normal)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        button.accessibilityLabel = "Encrypted"
        button.accessibilityHint = "Learn how your messages are protected"
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Sets what a tap does; nil leaves the line inert.
    public func configure(onTap: (() -> Void)?) {
        self.onTap = onTap
        button.isUserInteractionEnabled = onTap != nil
    }

    @objc private func tapped() {
        onTap?()
    }

    private static func title() -> NSAttributedString {
        let font = UIFont.default(size: 12, weight: .bold)
        let color = UIColor(Color.textSecondary)
        let symbol = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        func glyph(_ name: String) -> NSAttributedString {
            let attachment = NSTextAttachment()
            attachment.image = UIImage(systemName: name, withConfiguration: symbol)?
                .withTintColor(color, renderingMode: .alwaysOriginal)
            return NSAttributedString(attachment: attachment)
        }
        let result = NSMutableAttributedString(attributedString: glyph("lock.fill"))
        result.append(NSAttributedString(string: " Encrypted ", attributes: [.font: font, .foregroundColor: color]))
        result.append(glyph("chevron.right"))
        return result
    }
}
#endif
