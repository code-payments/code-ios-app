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
        let glyphSize: CGFloat = 12
        func glyph(_ icon: Icon) -> NSAttributedString {
            let attachment = NSTextAttachment()
            attachment.image = UIImage.icon(icon)
                .withTintColor(color, renderingMode: .alwaysOriginal)
            // Centred on the cap height, since an asset image has no baseline of its own.
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - glyphSize) / 2, width: glyphSize, height: glyphSize)
            return NSAttributedString(attachment: attachment)
        }
        let result = NSMutableAttributedString(attributedString: glyph(.lock))
        result.append(NSAttributedString(string: " Encrypted ", attributes: [.font: font, .foregroundColor: color]))
        result.append(glyph(.chevronRightMedium))
        return result
    }
}
#endif
