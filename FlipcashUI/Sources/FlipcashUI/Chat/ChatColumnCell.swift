//
//  ChatColumnCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// Base for a chat row that stacks a content view above an optional `ChatReceiptView` in a vertical
/// column, hugging the leading or trailing edge by sender. A subclass builds its content view (a
/// bubble or a card), hands it to `installColumn(content:)` from `init`, then calls `updateColumn(for:)`
/// from its own `configure`. The receipt collapses out of the column when the message carries none.
///
/// The column spans the full row and the stack's `alignment` does the hugging, rather than the column
/// hugging its content with one floating edge. A floating edge made the column's width the receipt's
/// for short messages, so clearing the receipt moved the column sideways by the difference and only
/// left the bubble still because the bubble's offset inside the stack moved the other way by exactly
/// as much. That cancellation holds on final values; mid-animation it is three separate layer
/// animations, and any one of them off the others' curve slides the bubble sideways.
public class ChatColumnCell: UICollectionViewCell {

    private let receipt = ChatReceiptView()
    private let column = UIStackView()
    /// The author's name above the first bubble of a run, in an attributed transcript. Hidden — and
    /// so collapsed out of the column — in every DM.
    private let authorName = UILabel()
    /// The author's face in the leading gutter, beside the last bubble of a run. A sibling of the
    /// column rather than a child of it, so the gutter's width is a leading inset on the column and
    /// a tall avatar can't grow a short-bubble row. It travels with the column under a reply swipe.
    private let authorAvatar = ChatAuthorAvatarView()
    /// The column's leading inset, widened to clear the gutter on an attributed incoming row.
    private var columnLeading: NSLayoutConstraint?
    /// The subclass's content view, kept so the retry recognizer can restrict itself to the visible
    /// row — the column spans the full width, so its own bounds are not the hit area.
    private var content: UIView?

    /// Fired when the user taps a failed row to retry; the argument is the message's stable id.
    var onRetry: ((String) -> Void)?
    /// Fired when the user taps the gutter face; the argument is that author's user id.
    var onAuthorTap: ((UserID) -> Void)?
    /// Who the gutter face currently belongs to, so the tap knows whose profile to open. Nil on
    /// every row that draws no face.
    private var authorID: UserID?
    /// The message's stable id while this row is failed and tappable; nil otherwise.
    private var retryID: String?
    /// Tap-to-retry recognizer, enabled only while this row is failed so non-failed bubbles don't
    /// consume taps (and a future single-tap affordance isn't pre-empted).
    private var retryTap: UITapGestureRecognizer?
    /// The id of the message this cell currently renders. The receipt animates only when the
    /// *same* row changes in place; a recycled cell reconfigured for a different id sets its line
    /// directly, so it never replays this cell's prior line (a reused failed cell flashing red).
    private var currentMessageID: String?

    /// Stacks `content` above the receipt and pins the column to all four edges of the contentView,
    /// so the cell self-sizes to the content plus the receipt line. Call once, from the subclass's
    /// `init`, after the content view exists.
    func installColumn(content: UIView) {
        self.content = content
        column.axis = .vertical
        column.spacing = 4
        // Figma puts the name 12pt Medium at 50% white, 4pt above the bubble — the column's own
        // spacing (nodes 10125:19169-19184).
        authorName.font = .default(size: 12, weight: .medium)
        authorName.textColor = UIColor(Color.textMain.opacity(Self.authorNameOpacity))
        authorName.isHidden = true
        column.addArrangedSubview(authorName)
        column.addArrangedSubview(content)
        column.addArrangedSubview(receipt)
        column.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(column)

        // The whole bubble + status line is the retry target (a generous hit area vs. the thin receipt
        // line). The recognizer is enabled only for a failed row (see updateColumn), so non-failed
        // bubbles don't consume taps and keep their long-press copy menu. It sits on the column rather
        // than the content view because a failed link row disables its bubble's interaction to stop
        // URL taps, which would otherwise take the retry with it.
        let tap = UITapGestureRecognizer(target: self, action: #selector(retryTapped))
        tap.isEnabled = false
        tap.delegate = self
        column.addGestureRecognizer(tap)
        retryTap = tap

        authorAvatar.translatesAutoresizingMaskIntoConstraints = false
        authorAvatar.isHidden = true
        // The face opens its owner's profile. Its own recognizer rather than the cell's, so it stays
        // independent of the retry tap on the column and of whatever the bubble does with a touch.
        authorAvatar.isUserInteractionEnabled = true
        authorAvatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(authorTapped)))
        contentView.addSubview(authorAvatar)

        let leading = column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.rowInset)
        columnLeading = leading
        NSLayoutConstraint.activate([
            leading,
            column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.rowInset),
            column.topAnchor.constraint(equalTo: contentView.topAnchor),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            // Leading and bottom only, with the view's own size constraints doing the rest: an
            // avatar pinned top as well would set a floor on the row's fitting height, and
            // `preferredLayoutAttributesFitting` would grow every short bubble to the gutter.
            authorAvatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.rowInset),
            authorAvatar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// The transcript's side margin, and the avatar gutter's own leading inset.
    static let rowInset: CGFloat = 12

    /// The author name's tint. Figma names every speaker in the same 50% white (node 9764:15123)
    /// rather than the per-person colour the quote panel uses, so a run of different senders reads
    /// as one transcript instead of a palette.
    private static let authorNameOpacity: Double = 0.5

    /// What an attributed incoming row gives up to the gutter: the circle plus the 8pt Figma puts
    /// between it and the bubble. Read by the layout to keep the bubble's max width proportional to
    /// the space the row actually has.
    public static let authorGutterWidth = ChatAuthorAvatarView.size + 8

    /// How far the row's content is dragged towards the trailing edge by the reply swipe.
    ///
    /// It moves the column and the gutter avatar, not the content view. `UICollectionViewCell.layoutSubviews` assigns
    /// `contentView.frame` on every pass, which cancels a transform there — and between ChatLayout's
    /// invalidations and the subview the swipe parents to the row, that pass runs often enough during
    /// a drag that the row never visibly moves. Auto Layout positions the column through `center` and
    /// `bounds`, which a transform composes with rather than fights — the same holds for the
    /// avatar.
    var swipeOffset: CGFloat {
        get { column.transform.tx }
        set {
            let transform: CGAffineTransform = newValue == 0 ? .identity : CGAffineTransform(translationX: newValue, y: 0)
            column.transform = transform
            // The face is part of the row, not furniture behind it, so it moves with the bubble it
            // belongs to rather than sliding out from under its own run.
            authorAvatar.transform = transform
        }
    }

    /// Self-sizes on height alone, at the width the layout asked for. The column spans the row, so
    /// the default implementation's compressed horizontal fit measures the cell at its content width
    /// instead — a width the layout then discards, having already forced the row to full width.
    public override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let width = layoutAttributes.frame.width
        let height = contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        layoutAttributes.frame.size = CGSize(width: width, height: height)
        return layoutAttributes
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        // A row recycled mid-swipe (or while the swipe's settle animation is still running) would
        // otherwise be dequeued still translated sideways, and draw its new message offset.
        swipeOffset = 0
        currentMessageID = nil
        retryID = nil
        retryTap?.isEnabled = false
        // Clear the line so a recycled cell never carries its prior row's text into the next use,
        // or animates away from it.
        receipt.reset()
        // Same for the attribution: a recycled cell would otherwise draw the previous author's name
        // and face for the frame before `updateColumn` runs.
        authorName.isHidden = true
        authorName.text = nil
        authorAvatar.isHidden = true
        authorAvatar.reset()
        authorID = nil
        columnLeading?.constant = Self.rowInset
    }

    /// Sets the status line and hugs the column to the sender's edge. Call from `configure`. The line
    /// itself comes from the mapping (`message.receipt`) and renders itself; the cell only decides
    /// whether the update animates, and makes a failed row tappable to retry.
    func updateColumn(for message: ChatMessage, authorImageData: Data? = nil) {
        // Cross-fade the receipt only when the *same* row changes in place (Delivered→Read, the settling
        // line revealing). A recycled or freshly dequeued cell renders a different row, so its line is set
        // directly — otherwise the cross-fade would replay this cell's prior line (a reused failed cell
        // flashing red "Not Delivered" before resolving to the real line).
        let isInPlaceUpdate = currentMessageID == message.id
        currentMessageID = message.id
        // A failed row is the only interactive/red one — every signal keys off that single condition.
        retryID = message.isFailed ? message.id : nil
        retryTap?.isEnabled = message.isFailed
        receipt.setReceipt(message.receipt, animated: isInPlaceUpdate && window != nil)
        column.alignment = message.sender == .me ? .trailing : .leading
        updateAttribution(for: message, authorImageData: authorImageData)
    }

    /// Names the author above the first bubble of their run and puts their face beside the last one,
    /// the way Figma draws a group transcript. `message.author` is nil in every DM and on the
    /// viewer's own rows, which collapses both back to the plain layout.
    private func updateAttribution(for message: ChatMessage, authorImageData: Data?) {
        guard let author = message.author, message.sender != .me else {
            authorName.isHidden = true
            authorName.text = nil
            authorAvatar.isHidden = true
            authorAvatar.reset()
            authorID = nil
            columnLeading?.constant = Self.rowInset
            return
        }
        authorID = author.id
        // The gutter is held open for the whole run, not just the row the face sits on, so the
        // bubbles of one run stay in a single column.
        columnLeading?.constant = Self.rowInset + Self.authorGutterWidth

        // The name opens a run. A roster that doesn't name this sender draws no label rather than an
        // empty line, which would read as stray padding above the bubble.
        authorName.text = author.name
        authorName.isHidden = message.isContinuationFromPrevious || author.name.isEmpty

        // The face closes it, so a run reads as one speaker with one avatar rather than a column of
        // repeated thumbnails.
        authorAvatar.isHidden = message.isContinuedByNext
        if !authorAvatar.isHidden {
            authorAvatar.configure(with: author, imageData: authorImageData)
        }
    }

    @objc private func retryTapped() {
        guard let retryID else { return }
        onRetry?(retryID)
    }

    @objc private func authorTapped() {
        guard let authorID else { return }
        onAuthorTap?(authorID)
    }
}

extension ChatColumnCell: UIGestureRecognizerDelegate {

    /// Keeps retry to the row the user can see. The column spans the full width so its frame doesn't
    /// move when the receipt collapses, which leaves the empty half of the row inside its bounds.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: column)
        return (content.map { $0.frame.contains(point) } ?? false) || (!receipt.isHidden && receipt.frame.contains(point))
    }
}
#endif
