//
//  ChatSystemMessageCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import SwiftUI
import UIKit

/// A server-authored notice, centred in the transcript (node 11721:879, option D): an info glyph,
/// then the text. No bubble, no fill, no sender, no gestures. The glyph is what tells it apart from
/// the date separator, which is also centred caption text.
public final class ChatSystemMessageCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatSystemMessageCell"

    private static let lineHeight: CGFloat = 18
    private static let verticalPadding: CGFloat = 6
    private static let glyphGap: CGFloat = 6
    private static let textMaxWidth: CGFloat = 250
    private static let textColor = UIColor(Color.textSecondary)
    private static let font = UIFont.appTextCaption

    private let label = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)

        let glyph = UIImageView(image: UIImage.icon(.circleInfo))
        glyph.tintColor = Self.textColor
        glyph.contentMode = .scaleAspectFit
        glyph.isAccessibilityElement = false
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        glyph.setContentCompressionResistancePriority(.required, for: .horizontal)
        glyph.translatesAutoresizingMaskIntoConstraints = false

        label.numberOfLines = 0
        label.textAlignment = .center
        label.preferredMaxLayoutWidth = Self.textMaxWidth
        label.translatesAutoresizingMaskIntoConstraints = false

        // Glyph and text are centred as one group, so a short notice sits in the middle of the row.
        let group = UIView()
        group.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(glyph)
        group.addSubview(label)
        contentView.addSubview(group)

        isAccessibilityElement = true
        accessibilityTraits = .staticText

        NSLayoutConstraint.activate([
            group.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            group.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: ChatColumnCell.rowInset),
            group.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalPadding),
            group.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.verticalPadding),

            // One line tall, so the glyph centres on the first line however many the text wraps to.
            glyph.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            glyph.topAnchor.constraint(equalTo: group.topAnchor),
            glyph.heightAnchor.constraint(equalToConstant: Self.lineHeight),
            glyph.widthAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: Self.glyphGap),
            label.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            label.topAnchor.constraint(equalTo: group.topAnchor),
            label.bottomAnchor.constraint(equalTo: group.bottomAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: Self.textMaxWidth),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows `text` unmodified, centred and wrapped at 250 points.
    public func configure(text: String) {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = Self.lineHeight
        style.maximumLineHeight = Self.lineHeight
        style.alignment = .center
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: Self.font,
            .foregroundColor: Self.textColor,
            .paragraphStyle: style,
            // Fixed line boxes sit the glyphs on the bottom; this centres them in the 18pt box.
            .baselineOffset: (Self.lineHeight - Self.font.lineHeight) / 2,
        ])
        accessibilityLabel = text
    }
}
#endif
