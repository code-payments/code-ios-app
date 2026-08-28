//
//  ChatReceiptView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The "Delivered" / "Read 3:42 PM" line under the user's latest sent bubble.
///
/// Two overlaid faces rather than one label, because Delivered giving way to Read is a swap of two
/// pieces of text in the same place: the outgoing one shrinks away while the incoming one grows in,
/// and a single label can only cross-fade its own contents. `front` always holds the current line
/// and is the only face constrained to the view's edges, so the row's height follows it alone and
/// an exiting `back` never disturbs the layout.
final class ChatReceiptView: UIView {

    /// Resting color of the receipt line (Delivered/Read).
    static let defaultColor = UIColor.white.withAlphaComponent(0.5)
    /// Color of the failed status line: the theme's error-text token, which tracks appearance changes.
    static let failedColor = UIColor(Color.textError)

    private let front = ChatReceiptFace()
    private let back = ChatReceiptFace()

    /// The line currently shown, or nil when the row carries none.
    private(set) var currentReceipt: ChatReceipt?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // A row carries no line until one is set, and the whole column is the retry target, so the
        // line itself never takes touches.
        isHidden = true
        isUserInteractionEnabled = false

        // Back first, so the incoming face draws over the one it is replacing.
        for face in [back, front] {
            face.translatesAutoresizingMaskIntoConstraints = false
            addSubview(face)
        }
        back.isHidden = true

        NSLayoutConstraint.activate([
            front.topAnchor.constraint(equalTo: topAnchor),
            front.bottomAnchor.constraint(equalTo: bottomAnchor),
            front.leadingAnchor.constraint(equalTo: leadingAnchor),
            front.trailingAnchor.constraint(equalTo: trailingAnchor),
            // The outgoing face is positioned, never measured: it must not hold the row open while
            // it shrinks away.
            back.trailingAnchor.constraint(equalTo: trailingAnchor),
            back.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Clears both faces and cancels any swap in flight. Call from `prepareForReuse` — a recycled
    /// cell must not carry its previous row's line, or animate away from it.
    func reset() {
        layer.removeAllAnimations()
        front.layer.removeAllAnimations()
        back.layer.removeAllAnimations()
        currentReceipt = nil
        front.setReceipt(nil)
        front.transform = .identity
        front.alpha = 1
        back.setReceipt(nil)
        back.isHidden = true
        back.transform = .identity
        back.alpha = 1
        isHidden = true
    }

    /// Shows `receipt`, animating the change when `animated` is set.
    ///
    /// Three transitions, deliberately different: appearing from nothing is the slow, gentle
    /// `delivered` reveal; swapping one status for another is the quicker, bouncier `read` spring,
    /// with the old line shrinking out as the new one grows in; clearing is instant, so the row
    /// collapses in step with the batch update rather than after a fade.
    func setReceipt(_ receipt: ChatReceipt?, animated: Bool) {
        guard receipt != currentReceipt else { return }
        let previous = currentReceipt
        currentReceipt = receipt

        guard let receipt else {
            reset()
            return
        }

        front.textColor = receipt.isFailed ? Self.failedColor : Self.defaultColor
        isHidden = false

        guard animated else {
            front.layer.removeAllAnimations()
            back.isHidden = true
            front.transform = .identity
            front.alpha = 1
            front.setReceipt(receipt)
            return
        }

        if let previous, previous.status != receipt.status {
            swap(from: previous, to: receipt)
        } else if previous == nil {
            reveal(receipt)
        } else {
            // Only the time moved (a re-render of the same Read line). Nothing to animate.
            front.setReceipt(receipt)
        }
    }

    /// nil → a line: grow in from `deliveredScale` about the centre.
    private func reveal(_ receipt: ChatReceipt) {
        front.setReceipt(receipt)
        front.transform = CGAffineTransform(scaleX: ChatMotion.deliveredScale, y: ChatMotion.deliveredScale)
        front.alpha = 0
        ChatMotion.delivered.animate {
            self.front.transform = .identity
            self.front.alpha = 1
        }
    }

    /// Delivered → Read: the old line shrinks and fades out where it stands while the new one grows
    /// and fades in over it. The spec tunes both slide distances to zero, so this is scale and
    /// opacity only — the line stays put and changes.
    private func swap(from previous: ChatReceipt, to receipt: ChatReceipt) {
        back.textColor = previous.isFailed ? Self.failedColor : Self.defaultColor
        back.setReceipt(previous)
        back.isHidden = false
        back.transform = .identity
        back.alpha = 1

        front.setReceipt(receipt)
        front.transform = CGAffineTransform(scaleX: ChatMotion.readEnterScale, y: ChatMotion.readEnterScale)
        front.alpha = 0

        ChatMotion.read.animate {
            self.back.transform = CGAffineTransform(scaleX: ChatMotion.deliveredExitScale, y: ChatMotion.deliveredExitScale)
            self.back.alpha = 0
            self.front.transform = .identity
            self.front.alpha = 1
        } completion: { _ in
            self.back.isHidden = true
            self.back.transform = .identity
        }
    }

    // MARK: - Test hooks

    /// The status run currently on the front face, or nil when the line is empty.
    var currentStatusText: String? { currentReceipt == nil ? nil : front.statusText }
    /// The timestamp run currently on the front face.
    var currentTimeText: String? { currentReceipt == nil ? nil : front.timeText }
    /// The status run on the back face — whatever is on its way out.
    var outgoingStatusText: String? { back.statusText }
    /// The front face's colour, which is what makes a failed line read as red.
    var currentColor: UIColor { front.textColor }
    /// The back face's colour — the outgoing state's, not the arriving one's.
    var outgoingColor: UIColor { back.textColor }
}

/// One rendering of a receipt line: the status in the heavier weight, the time in the lighter one.
///
/// Two labels rather than one attributed string because the pair is also a layout — a fixed gap
/// between the halves, and trailing padding that keeps the line off the column's edge.
private final class ChatReceiptFace: UIView {

    /// Gap between the status word and the time.
    private static let gap: CGFloat = 4
    /// Keeps the line off the column's trailing edge.
    private static let trailingPadding: CGFloat = 10
    private static let fontSize: CGFloat = 11

    private let status = UILabel()
    private let time = UILabel()
    private let row = UIStackView()

    var textColor: UIColor = ChatReceiptView.defaultColor {
        didSet {
            status.textColor = textColor
            time.textColor = textColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        status.font = .default(size: Self.fontSize, weight: .bold)
        time.font = .default(size: Self.fontSize, weight: .medium)
        for label in [status, time] {
            label.textColor = textColor
            label.numberOfLines = 1
        }

        row.axis = .horizontal
        row.spacing = Self.gap
        row.alignment = .firstBaseline
        row.addArrangedSubview(status)
        row.addArrangedSubview(time)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingPadding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setReceipt(_ receipt: ChatReceipt?) {
        status.text = receipt?.status
        time.text = receipt?.time
        time.isHidden = receipt?.time == nil
    }

    var statusText: String? { status.text }
    var timeText: String? { time.isHidden ? nil : time.text }
}
#endif
