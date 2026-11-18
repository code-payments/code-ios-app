//
//  ChatSystemMessageCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import SwiftUI
import UIKit
import FlipcashCore

/// A server-authored notice, centred in the transcript (node 11721:879): the text alone. No bubble,
/// no fill, no glyph, no sender, no gestures. An invite join's inviter is the one name drawn bold,
/// and tapping it opens that user's profile.
public final class ChatSystemMessageCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatSystemMessageCell"

    private static let lineHeight: CGFloat = 18
    private static let verticalPadding: CGFloat = 6
    private static let textMaxWidth: CGFloat = 250
    private static let textColor = UIColor(Color.textSecondary)
    private static let font = UIFont.appTextCaption
    private static let linkFont = UIFont.default(size: 12, weight: .bold)

    private let label = UILabel()
    private var userLink: SystemNoticeUserLink?
    private var onUserTap: ((UserID) -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)

        label.numberOfLines = 0
        label.textAlignment = .center
        label.preferredMaxLayoutWidth = Self.textMaxWidth
        label.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(label)

        isAccessibilityElement = true
        accessibilityTraits = .staticText

        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(labelTapped(_:))))

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: ChatColumnCell.rowInset),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalPadding),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.verticalPadding),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: Self.textMaxWidth),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows `text` unmodified, centred and wrapped at 250 points. `userLink`'s name is drawn bold,
    /// and a tap on it calls `onUserTap`; a nil `onUserTap` leaves it inert.
    public func configure(text: String, userLink: SystemNoticeUserLink? = nil, onUserTap: ((UserID) -> Void)? = nil) {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = Self.lineHeight
        style.maximumLineHeight = Self.lineHeight
        style.alignment = .center
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: Self.font,
            .foregroundColor: Self.textColor,
            .paragraphStyle: style,
            // Fixed line boxes sit the glyphs on the bottom; this centres them in the 18pt box.
            .baselineOffset: (Self.lineHeight - Self.font.lineHeight) / 2,
        ])
        let link = userLink.flatMap { NSMaxRange($0.range) <= attributed.length ? $0 : nil }
        if let link {
            attributed.addAttribute(.font, value: Self.linkFont, range: link.range)
        }
        label.attributedText = attributed
        self.userLink = link
        self.onUserTap = onUserTap
        let tappable = link != nil && onUserTap != nil
        label.isUserInteractionEnabled = tappable
        accessibilityLabel = text
        accessibilityTraits = tappable ? [.staticText, .button] : .staticText
    }

    // VoiceOver reads the notice as one element, so activating it stands in for the tap on the name.
    public override func accessibilityActivate() -> Bool {
        guard let userLink, let onUserTap else { return false }
        onUserTap(userLink.userID)
        return true
    }

    @objc private func labelTapped(_ recognizer: UITapGestureRecognizer) {
        guard let userLink, let onUserTap, let text = label.attributedText,
              let index = characterIndex(at: recognizer.location(in: label), in: text),
              NSLocationInRange(index, userLink.range) else { return }
        onUserTap(userLink.userID)
    }

    /// The character under `point` in the label, laid out the way the label lays out `text`.
    private func characterIndex(at point: CGPoint, in text: NSAttributedString) -> Int? {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: label.bounds.size)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = label.numberOfLines
        container.lineBreakMode = label.lineBreakMode
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let glyph = layout.glyphIndex(for: point, in: container)
        // A point beside the text maps to the nearest glyph; only one inside its box counts.
        guard layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point) else {
            return nil
        }
        return layout.characterIndexForGlyph(at: glyph)
    }
}
#endif
