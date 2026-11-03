//
//  SendBackRowView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The full-width row a cash card attaches to its bottom edge under a DM's opening payment: a white
/// "Send Back" action, a spinner while the return is sending, or a quiet "Sent Back" footer. The
/// card's shape mask rounds its lower corners.
final class SendBackRowView: UIControl {

    /// The row's height in every state (design node 13296:491).
    static let height: CGFloat = 48

    private static let actionFill = UIColor(Color.textMain)
    private static let actionText = UIColor(Color.backgroundMain)
    private static let dividerColor = UIColor.white.withAlphaComponent(0.08)
    /// The card's caption style, so "Sent Back" reads as one of the card's lines.
    private static let footerFont = UIFont.appTextHeading
    private static let footerColor = UIColor.white.withAlphaComponent(0.5)

    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let divider = UIView()
    /// The state last applied; read by tests.
    private(set) var displayedState: ChatCashContent.SendBack = .available

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = Self.actionText
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = Self.dividerColor
        divider.isUserInteractionEnabled = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        [label, spinner, divider].forEach(addSubview)
        isAccessibilityElement = true

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Dims the action while pressed, as the card dims for its own tap.
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted && isEnabled ? 0.6 : 1 }
    }

    func apply(_ state: ChatCashContent.SendBack) {
        displayedState = state
        switch state {
        case .available:
            backgroundColor = Self.actionFill
            divider.isHidden = false
            label.isHidden = false
            label.text = "Send Back"
            label.font = .appTextSmall
            label.textColor = Self.actionText
            spinner.stopAnimating()
            isEnabled = true
            accessibilityLabel = "Send Back"
            accessibilityTraits = .button
        case .sending:
            backgroundColor = Self.actionFill
            divider.isHidden = false
            label.isHidden = true
            spinner.startAnimating()
            isEnabled = false
            accessibilityLabel = "Sending back"
            accessibilityTraits = [.button, .notEnabled]
        case .sentBack:
            backgroundColor = .clear
            divider.isHidden = true
            label.isHidden = false
            label.text = "Sent Back"
            label.font = Self.footerFont
            label.textColor = Self.footerColor
            spinner.stopAnimating()
            isEnabled = false
            accessibilityLabel = "Sent Back"
            accessibilityTraits = .staticText
        }
        alpha = 1
    }
}
#endif
