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

    /// Fired when the user taps a failed row to retry; the argument is the message's stable id.
    var onRetry: ((String) -> Void)?
    /// The message's stable id while this row is failed and tappable; nil otherwise.
    private var retryID: String?

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

        // The whole bubble + status line is the retry target (a generous hit area vs. the thin
        // receipt line), but a tap only fires onRetry when this row is failed — `retryTapped` checks
        // retryID, so non-failed rows ignore taps and keep their long-press copy menu.
        column.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryTapped)))

        leadingConstraint = column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: contentView.topAnchor),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        retryID = nil
    }

    /// Sets the status line and hugs the column to the sender's edge. Call from `configure`. The text
    /// is supplied by the mapping (`message.receipt`); this only styles it — a failed row turns red and
    /// becomes tappable to retry.
    func updateColumn(for message: ChatMessage) {
        switch message.deliveryState {
        case .normal, .sending:
            retryID = nil
            receipt.textColor = ChatReceiptLabel.defaultColor
        case .failed:
            retryID = message.id
            receipt.textColor = ChatReceiptLabel.failedColor
        }
        // A cell already in the window is being reconfigured in place (Delivered→Read, sending→
        // delivered, the line clearing as a newer sent message takes it over), so cross-fade the
        // change. A freshly dequeued cell isn't in the window yet, so it's set without animation — a
        // scroll-in or a send shouldn't flash the line.
        setReceipt(message.receipt, animated: window != nil)
        column.alignment = message.sender == .me ? .trailing : .leading
        applyAlignment(isFromSelf: message.sender == .me)
    }

    @objc private func retryTapped() {
        guard let retryID else { return }
        onRetry?(retryID)
    }

    private func setReceipt(_ text: String?, animated: Bool) {
        guard receipt.text != text else { return }
        // Cross-fade the line in (nil→text) and across the Delivered→Read swap; let it snap away when
        // it clears so the row collapses in step with the batch update rather than after the fade. The
        // visibility change is applied synchronously, outside the transition, so the cell's self-sized
        // height never lags the cross-fade.
        if animated, text != nil {
            receipt.isHidden = false
            UIView.transition(with: receipt, duration: 0.25, options: .transitionCrossDissolve) {
                self.receipt.text = text
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
