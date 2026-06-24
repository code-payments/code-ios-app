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
    func updateColumn(for message: ChatMessage) {
        receipt.text = message.receipt
        receipt.isHidden = message.receipt == nil
        column.alignment = message.sender == .me ? .trailing : .leading
        applyAlignment(isFromSelf: message.sender == .me)
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
