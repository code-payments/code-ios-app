//
//  ChatRequestEventCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import SwiftUI
import UIKit
import FlipcashCore

/// A payment request's share paid, share marked paid, or close, as one centred line in the
/// transcript with the system row's metrics. A share payment sits between two fading rules and
/// shows its amount in the success colour; the other two are plain. A tap on the row opens the
/// request's details, which the collection view's selection delivers.
public final class ChatRequestEventCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatRequestEventCell"

    /// The system row's metrics (`ChatSystemMessageCell`).
    private static let lineHeight: CGFloat = 18
    private static let verticalPadding: CGFloat = 6
    static let textMaxWidth: CGFloat = 250
    private static let textColor = UIColor(Color.textSecondary)
    private static let amountColor = UIColor(Color.textSuccess)
    private static let font = UIFont.appTextCaption
    private static let emphasisFont = UIFont.default(size: 12, weight: .bold)

    static let ringDiameter: CGFloat = 14
    private static let ringGap: CGFloat = 4
    private static let ruleGap: CGFloat = 8
    private static let ruleMinWidth: CGFloat = 16
    private static let ruleOpacity: Float = 0.28

    private let leadingRule = FadingRuleView(fadesToward: .leading)
    private let trailingRule = FadingRuleView(fadesToward: .trailing)
    private let firstLabel = UILabel()
    private let secondLabel = UILabel()
    private let firstLine = UIStackView()
    private let secondLine = UIStackView()
    private let ring: any UIView & UIContentView
    private var captionWidth: NSLayoutConstraint!

    public override init(frame: CGRect) {
        ring = UIHostingConfiguration { RequestEventRing(fraction: 0, rowID: "") }
            .margins(.all, 0)
            .makeContentView()
        super.init(frame: frame)

        for label in [firstLabel, secondLabel] {
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.heightAnchor.constraint(equalToConstant: Self.lineHeight).isActive = true
        }
        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: Self.ringDiameter),
            ring.heightAnchor.constraint(equalToConstant: Self.ringDiameter),
        ])

        for line in [firstLine, secondLine] {
            line.axis = .horizontal
            line.alignment = .center
            line.spacing = Self.ringGap
        }
        firstLine.addArrangedSubview(firstLabel)
        secondLine.addArrangedSubview(secondLabel)

        let caption = UIStackView(arrangedSubviews: [firstLine, secondLine])
        caption.axis = .vertical
        caption.alignment = .center
        caption.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [leadingRule, caption, trailingRule])
        row.axis = .horizontal
        // Top-aligned, with each rule one line tall: a caption that wraps keeps its rules beside
        // line 1.
        row.alignment = .top
        row.spacing = Self.ruleGap
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        captionWidth = caption.widthAnchor.constraint(lessThanOrEqualToConstant: Self.textMaxWidth)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: ChatColumnCell.rowInset),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -ChatColumnCell.rowInset),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalPadding),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.verticalPadding),
            leadingRule.widthAnchor.constraint(equalTo: trailingRule.widthAnchor),
            leadingRule.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.ruleMinWidth),
            leadingRule.heightAnchor.constraint(equalToConstant: Self.lineHeight),
            trailingRule.heightAnchor.constraint(equalToConstant: Self.lineHeight),
            captionWidth,
        ])
        leadingRule.layer.opacity = Self.ruleOpacity
        trailingRule.layer.opacity = Self.ruleOpacity

        isAccessibilityElement = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Draws `event`, cut to fit the narrower of the system row's 250 points and `maxWidth`, the
    /// room the row has between its rules.
    public func configure(with event: ChatRequestEvent, maxWidth: CGFloat) {
        let width = min(Self.textMaxWidth, maxWidth)
        captionWidth.constant = width
        let showsRing = event.ringFraction != nil
        let fit = event.fit(maxWidth: Double(width)) { caption, title in
            Double(Self.width(of: Self.line(caption: caption, amount: event.amount, title: title, separator: event.titleSeparator), ring: showsRing && title != nil))
        }

        let showsRules: Bool = switch event.kind {
        case .sharePayment:        true
        case .markedPaid, .closed: false
        }
        leadingRule.alpha = showsRules ? 1 : 0
        trailingRule.alpha = showsRules ? 1 : 0

        if fit.wraps {
            firstLabel.attributedText = Self.line(caption: fit.caption, amount: event.amount, title: nil, separator: "")
            secondLabel.attributedText = fit.title.map { Self.text($0, font: Self.font, color: Self.textColor) }
        } else {
            firstLabel.attributedText = Self.line(caption: fit.caption, amount: event.amount, title: fit.title, separator: event.titleSeparator)
            secondLabel.attributedText = nil
        }
        secondLine.isHidden = !fit.wraps

        // The ring follows the title onto whichever line holds it.
        ring.removeFromSuperview()
        if let fraction = event.ringFraction, fit.title != nil {
            (fit.wraps ? secondLine : firstLine).addArrangedSubview(ring)
            // Keyed by row, so a recycled cell shows the new row's ring without sweeping to it.
            ring.configuration = UIHostingConfiguration { RequestEventRing(fraction: fraction, rowID: event.id) }
                .margins(.all, 0)
        }

        accessibilityLabel = event.spokenText
        accessibilityTraits = event.requestID == nil ? .staticText : [.staticText, .button]
    }

    /// One line of the row: the caption, the amount, and the title after `separator`.
    private static func line(caption: [ChatRequestEvent.Span], amount: String?, title: String?, separator: String) -> NSAttributedString {
        let line = NSMutableAttributedString()
        for span in caption {
            line.append(text(span.text, font: span.isEmphasized ? emphasisFont : font, color: textColor))
        }
        if let amount {
            line.append(text(" ", font: font, color: textColor))
            line.append(text(amount, font: emphasisFont, color: amountColor))
        }
        if let title {
            line.append(text(separator + title, font: font, color: textColor))
        }
        return line
    }

    private static func text(_ string: String, font: UIFont, color: UIColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    private static func width(of line: NSAttributedString, ring: Bool) -> CGFloat {
        ceil(line.size().width) + (ring ? ringGap + ringDiameter : 0)
    }
}

/// The request's progress ring at the row's size: the deck's ring, scaled down whole so its stroke
/// and "$" shrink with it.
private struct RequestEventRing: View {

    let fraction: Double
    let rowID: String

    /// The ring's own smallest size, which the row scales from.
    private static let sourceDiameter: CGFloat = 26

    var body: some View {
        PaymentRequestRing(fraction: fraction, diameter: Self.sourceDiameter)
            .scaleEffect(ChatRequestEventCell.ringDiameter / Self.sourceDiameter)
            .frame(width: ChatRequestEventCell.ringDiameter, height: ChatRequestEventCell.ringDiameter)
            .id(rowID)
    }
}

/// A one-point rule, drawn through the middle of the view, that fades from the success colour
/// beside the text to clear at its outer end.
private final class FadingRuleView: UIView {

    enum Edge { case leading, trailing }

    private let gradient = CAGradientLayer()

    init(fadesToward edge: Edge) {
        super.init(frame: .zero)
        let color = UIColor(Color.textSuccess)
        layer.addSublayer(gradient)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        let clear = color.withAlphaComponent(0).cgColor
        gradient.colors = switch edge {
        case .leading:  [clear, color.cgColor]
        case .trailing: [color.cgColor, clear]
        }
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = CGRect(x: 0, y: (bounds.height - 1) / 2, width: bounds.width, height: 1)
        CATransaction.commit()
    }
}
#endif
