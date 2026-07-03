//
//  ChatColumnCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// Base for a chat row that stacks a content view above an optional `ChatReceiptLabel` in a vertical
/// column, hugging the leading or trailing edge by sender. A subclass builds its content view (a
/// bubble or a card), hands it to `installColumn(content:)` from `init`, then calls `updateColumn(for:)`
/// from its own `configure`. The receipt collapses out of the column when the message carries none.
public class ChatColumnCell: UICollectionViewCell {

    private let receipt = ChatReceiptLabel()
    private let column = UIStackView()
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    /// Fired when the user taps a failed row to retry; the argument is the message's stable id.
    var onRetry: ((String) -> Void)?
    /// The message's stable id while this row is failed and tappable; nil otherwise.
    private var retryID: String?
    /// Tap-to-retry recognizer, enabled only while this row is failed so non-failed bubbles don't
    /// consume taps (and a future single-tap affordance isn't pre-empted).
    private var retryTap: UITapGestureRecognizer?
    /// The id of the message this cell currently renders. The receipt is cross-faded only when the
    /// *same* row changes in place; a recycled cell reconfigured for a different id sets its line
    /// directly, so it never replays this cell's prior line (a reused failed cell flashing red).
    private var currentMessageID: String?

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

        // The whole bubble + status line is the retry target (a generous hit area vs. the thin receipt
        // line). The recognizer is enabled only for a failed row (see updateColumn), so non-failed
        // bubbles don't consume taps and keep their long-press copy menu.
        let tap = UITapGestureRecognizer(target: self, action: #selector(retryTapped))
        tap.isEnabled = false
        column.addGestureRecognizer(tap)
        retryTap = tap

        leadingConstraint = column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: contentView.topAnchor),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        currentMessageID = nil
        retryID = nil
        retryTap?.isEnabled = false
        // Clear the line so a recycled cell never carries its prior row's text/color — or a
        // mid-flight reveal's alpha/transform — into the next use.
        receipt.text = nil
        receipt.isHidden = true
        receipt.textColor = ChatReceiptLabel.defaultColor
        receipt.alpha = 1
        receipt.transform = .identity
    }

    /// Sets the status line and hugs the column to the sender's edge. Call from `configure`. The text
    /// is supplied by the mapping (`message.receipt`); this only styles it — a failed row turns red and
    /// becomes tappable to retry.
    func updateColumn(for message: ChatMessage) {
        // Animate the receipt only when the *same* row changes in place (Delivered→Read, the settling
        // line revealing). A recycled or freshly dequeued cell renders a different row, so its line is set
        // directly — otherwise the animation would replay this cell's prior line (a reused failed cell
        // flashing red "Not Delivered" before resolving to the real line).
        let inPlace = isInPlaceUpdate(for: message)
        currentMessageID = message.id
        // A failed row is the only interactive/red one — every signal keys off that single condition.
        retryID = message.isFailed ? message.id : nil
        receipt.textColor = message.isFailed ? ChatReceiptLabel.failedColor : ChatReceiptLabel.defaultColor
        retryTap?.isEnabled = message.isFailed
        setReceipt(message.receipt, animated: inPlace)
        column.alignment = message.sender == .me ? .trailing : .leading
        applyAlignment(isFromSelf: message.sender == .me)
    }

    /// Whether `message` re-renders the row this cell already shows, on screen — the gate for
    /// view-level change animations (receipt reveal, corner morph). A recycled or freshly dequeued
    /// cell renders a *different* row, so its changes apply directly instead of replaying an
    /// animation that belongs to another message.
    func isInPlaceUpdate(for message: ChatMessage) -> Bool {
        currentMessageID == message.id && window != nil
    }

    @objc private func retryTapped() {
        guard let retryID else { return }
        onRetry?(retryID)
    }

    private func setReceipt(_ text: String?, animated: Bool) {
        guard receipt.text != text else { return }
        // A revealing line scale/fades in (the prototype's "Delivered" pop) and a text swap
        // cross-fades in place (Delivered→Read); the line snaps away when it clears so the row
        // collapses in step with the batch update rather than after the fade. Text and visibility
        // are applied synchronously, outside the animation, so the cell's self-sized height never
        // lags the motion.
        if animated, text != nil {
            if receipt.isHidden {
                receipt.text = text
                receipt.isHidden = false
                receipt.alpha = 0
                receipt.transform = CGAffineTransform(scaleX: ChatMotion.receiptRevealScale, y: ChatMotion.receiptRevealScale)
                UIView.animate(springDuration: ChatMotion.receiptReveal.duration, bounce: ChatMotion.receiptReveal.bounce) {
                    self.receipt.alpha = 1
                    self.receipt.transform = .identity
                }
            } else {
                UIView.transition(with: receipt, duration: ChatMotion.receiptSwapDuration, options: .transitionCrossDissolve) {
                    self.receipt.text = text
                }
            }
        } else {
            receipt.text = text
            receipt.isHidden = text == nil
            receipt.alpha = 1
            receipt.transform = .identity
        }
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
