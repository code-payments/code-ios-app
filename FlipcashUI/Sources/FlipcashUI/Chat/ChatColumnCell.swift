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
    /// The id of the message this cell currently renders — the input to `isInPlaceUpdate`.
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
        // Drop a mid-flight reveal so it can't play over the next row's line.
        receipt.layer.removeAllAnimations()
        receipt.text = nil
        receipt.isHidden = true
        receipt.textColor = ChatReceiptLabel.defaultColor
    }

    /// Styles the status line and alignment for `message`, returning whether this re-rendered
    /// the row already on screen. Call first from `configure`, before the cell adopts the new id.
    func updateColumn(for message: ChatMessage) -> Bool {
        let inPlace = isInPlaceUpdate(for: message)
        currentMessageID = message.id
        // A failed row is the only interactive/red one — every signal keys off that single condition.
        retryID = message.isFailed ? message.id : nil
        receipt.textColor = message.isFailed ? ChatReceiptLabel.failedColor : ChatReceiptLabel.defaultColor
        retryTap?.isEnabled = message.isFailed
        setReceipt(message.receipt, animated: inPlace)
        column.alignment = message.sender == .me ? .trailing : .leading
        applyAlignment(isFromSelf: message.sender == .me)
        return inPlace
    }

    /// Whether `message` re-renders the row this cell already shows on screen — the gate keeping
    /// recycled cells from replaying change animations that belong to another message.
    private func isInPlaceUpdate(for message: ChatMessage) -> Bool {
        currentMessageID == message.id && window != nil
    }

    @objc private func retryTapped() {
        guard let retryID else { return }
        onRetry?(retryID)
    }

    private func setReceipt(_ text: String?, animated: Bool) {
        guard receipt.text != text else { return }
        // Text and visibility apply synchronously so the cell's self-sized height never lags.
        if animated, text != nil {
            if receipt.isHidden {
                // The starting state is fenced off the ambient batch spring, or the pop is
                // captured mid-value and lost.
                UIView.performWithoutAnimation {
                    receipt.text = text
                    receipt.isHidden = false
                    receipt.alpha = 0
                    receipt.transform = CGAffineTransform(scaleX: ChatMotion.receiptRevealScale, y: ChatMotion.receiptRevealScale)
                }
                UIView.animate(springDuration: ChatMotion.receiptReveal.duration, bounce: ChatMotion.receiptReveal.bounce, options: [.overrideInheritedDuration]) {
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
