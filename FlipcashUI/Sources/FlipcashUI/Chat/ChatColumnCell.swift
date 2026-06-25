//
//  ChatColumnCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// Base for a chat row that stacks a content view above an optional `ChatReceiptLabel` in a vertical
/// column, hugging the leading or trailing edge by sender. A subclass builds its content view (a
/// bubble or a card), hands it to `installColumn(content:)` from `init`, then calls `updateColumn(for:)`
/// from its own `configure`. The receipt collapses out of the column when the message carries none.
public class ChatColumnCell: UICollectionViewCell {

    private let receipt = ChatReceiptLabel()
    private let column = UIStackView()
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    /// Duration of the receipt fade-in and the in-place Delivered→Read cross-fade.
    private static let receiptFadeDuration: TimeInterval = 0.25

    /// Stacks `content` above the receipt and pins the column into the contentView, pinning top and
    /// bottom so the cell self-sizes to the content plus the receipt line. Call once, from the
    /// subclass's `init`, after the content view exists.
    func installColumn(content: UIView) {
        column.axis = .vertical
        column.spacing = 4
        column.addArrangedSubview(content)
        column.addArrangedSubview(receipt)
        column.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(column)

        leadingConstraint = column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: contentView.topAnchor),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// Sets the receipt line and hugs the column to the sender's edge. Call from `configure`.
    /// `revealsReceiptAfterSettling` is set only for a just-sent message's inserting cell: the line is
    /// held hidden and faded in by `revealHeldReceipt()` once the controller reports the insert has
    /// settled, instead of popping in with the bubble.
    func updateColumn(for message: ChatMessage, revealsReceiptAfterSettling: Bool = false) {
        setReceipt(message.receipt, animated: window != nil, held: revealsReceiptAfterSettling)
        column.alignment = message.sender == .me ? .trailing : .leading
        applyAlignment(isFromSelf: message.sender == .me)
    }

    private func setReceipt(_ text: String?, animated: Bool, held: Bool) {
        guard receipt.text != text else { return }
        if let text, held {
            // A just-sent message's inserting cell: reserve the line's space so the bubble lands in its
            // final spot, but hold it hidden. `revealHeldReceipt()` fades it in once the controller
            // reports the insert has settled — the delivery state shouldn't pop in with the bubble.
            receipt.isHidden = false
            receipt.text = text
            receipt.alpha = 0
        } else if let text, receipt.alpha < 1 {
            // A swap arrived while the line was still held (the read pointer advanced before the insert
            // settled): update the text but stay held, so the pending `revealHeldReceipt()` fades the
            // new text in once the insert settles — rather than colliding a cross-dissolve with the reveal.
            receipt.text = text
        } else if animated, text != nil {
            // A cell already in the window is being reconfigured in place (Delivered→Read), so
            // cross-fade the swap. alpha is restored first in case the cell was mid-hold. The
            // visibility change is applied synchronously, outside the transition, so the cell's
            // self-sized height never lags the cross-fade.
            receipt.alpha = 1
            receipt.isHidden = false
            UIView.transition(with: receipt, duration: Self.receiptFadeDuration, options: .transitionCrossDissolve) {
                self.receipt.text = text
            }
        } else {
            // Set without animation: a first open or a scroll-in shows the line already in place; a
            // newer sent message clearing the line lets it snap away so the row collapses in step with
            // the batch update rather than after a fade.
            receipt.alpha = 1
            receipt.text = text
            receipt.isHidden = text == nil
        }
    }

    /// Fade in a receipt that was held hidden for its inserting cell, now that the insert has settled.
    /// A no-op for any cell not currently holding one, so the controller can call it on every visible
    /// cell after a batch update without tracking which cell inserted.
    func revealHeldReceipt() {
        guard receipt.alpha < 1 else { return }
        UIView.animate(withDuration: Self.receiptFadeDuration) { self.receipt.alpha = 1 }
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        // Clear the receipt fully: a stale text would let `setReceipt`'s `text != text` guard skip the
        // hold for a recycled cell whose previous occupant ended on the same string ("Delivered").
        receipt.text = nil
        receipt.isHidden = true
        receipt.alpha = 1
    }

    /// Exactly one horizontal edge is pinned, so the column hugs its sender's side and the opposite
    /// edge floats. Both edges are deactivated before the wanted one is activated: a recycled cell
    /// still carries its prior encapsulated layout width, so momentarily pinning both edges
    /// over-constrains it and trips Auto Layout's unsatisfiable-constraints check.
    private func applyAlignment(isFromSelf: Bool) {
        NSLayoutConstraint.deactivate([leadingConstraint, trailingConstraint])
        (isFromSelf ? trailingConstraint : leadingConstraint).isActive = true
    }
}
#endif
