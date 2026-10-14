//
//  ChatSystemMessageCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// A server-authored notice, drawn as a leading-aligned line: a ringed info glyph in the member-avatar
/// gutter, then the text at the member bubble column. No bubble, no fill, no sender, no gestures.
public final class ChatSystemMessageCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatSystemMessageCell"

    private static let slotSize = ChatAuthorAvatarView.size
    private static let lineHeight: CGFloat = 16
    private static let verticalPadding: CGFloat = 6
    private static let textColor = UIColor.white.withAlphaComponent(0.5)
    private static let font = UIFont.default(size: 13, weight: .regular)

    private let label = UILabel()
    private let textWidth: NSLayoutConstraint

    public override init(frame: CGRect) {
        textWidth = label.widthAnchor.constraint(equalToConstant: 0)
        super.init(frame: frame)

        let slot = UIView()
        slot.layer.cornerRadius = Self.slotSize / 2
        slot.layer.borderWidth = 1 / UITraitCollection.current.displayScale
        slot.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        slot.translatesAutoresizingMaskIntoConstraints = false

        let glyph = UIImageView(image: UIImage(systemName: "info.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14)))
        glyph.tintColor = Self.textColor
        glyph.contentMode = .center
        glyph.isAccessibilityElement = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(glyph)

        label.numberOfLines = 0
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(slot)
        contentView.addSubview(label)

        // Below the width pin so a row narrower than the column squeezes the text, not the layout.
        textWidth.priority = .defaultHigh
        isAccessibilityElement = true
        accessibilityTraits = .staticText

        let textLeading = ChatColumnCell.rowInset + ChatColumnCell.authorGutterWidth
        NSLayoutConstraint.activate([
            slot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: ChatColumnCell.rowInset),
            slot.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalPadding),
            slot.widthAnchor.constraint(equalToConstant: Self.slotSize),
            slot.heightAnchor.constraint(equalToConstant: Self.slotSize),
            slot.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Self.verticalPadding),
            glyph.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: slot.centerYAnchor),

            // The first line centres on the slot: its 16pt box starts (24 - 16) / 2 below the slot top.
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: textLeading),
            label.topAnchor.constraint(equalTo: slot.topAnchor, constant: (Self.slotSize - Self.lineHeight) / 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -ChatColumnCell.rowInset),
            label.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Self.verticalPadding),
            textWidth,
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows `text` unmodified, wrapped to `maxWidth` points.
    public func configure(text: String, maxWidth: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = Self.lineHeight
        style.maximumLineHeight = Self.lineHeight
        style.alignment = .left
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: Self.font,
            .foregroundColor: Self.textColor,
            .paragraphStyle: style,
            // Fixed line boxes sit the glyphs on the bottom; this centres them in the 16pt box.
            .baselineOffset: (Self.lineHeight - Self.font.lineHeight) / 2,
        ])
        textWidth.constant = maxWidth
        accessibilityLabel = text
    }
}
#endif
