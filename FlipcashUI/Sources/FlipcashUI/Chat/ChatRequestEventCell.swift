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
/// transcript with the system row's metrics. The amount is semibold in the caption's colour. A tap
/// on the row opens the request's details, which the collection view's selection delivers.
public final class ChatRequestEventCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatRequestEventCell"

    /// The system row's metrics (`ChatSystemMessageCell`).
    private static let lineHeight: CGFloat = 18
    private static let verticalPadding: CGFloat = 6
    static let textMaxWidth: CGFloat = 250
    private static let textColor = UIColor(Color.textSecondary)
    private static let font = UIFont.appTextCaption
    private static let emphasisFont = UIFont.default(size: 12, weight: .bold)

    static let ringDiameter: CGFloat = 14
    private static let ringGap: CGFloat = 4

    private let lines = UIStackView()
    private let ring: any UIView & UIContentView
    private var captionWidth: NSLayoutConstraint!

    public override init(frame: CGRect) {
        ring = UIHostingConfiguration { RequestEventRing(fraction: 0, rowID: "") }
            .margins(.all, 0)
            .makeContentView()
        super.init(frame: frame)

        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: Self.ringDiameter),
            ring.heightAnchor.constraint(equalToConstant: Self.ringDiameter),
        ])

        lines.axis = .vertical
        lines.alignment = .center
        lines.setContentHuggingPriority(.required, for: .horizontal)

        lines.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(lines)

        captionWidth = lines.widthAnchor.constraint(lessThanOrEqualToConstant: Self.textMaxWidth)
        NSLayoutConstraint.activate([
            lines.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            lines.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: ChatColumnCell.rowInset),
            lines.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -ChatColumnCell.rowInset),
            lines.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalPadding),
            lines.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.verticalPadding),
            captionWidth,
        ])

        isAccessibilityElement = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Draws `event` whole, in the narrower of the system row's 250 points and `maxWidth`, the room
    /// the row has between its rules. A row that doesn't fit on one line takes the caption and
    /// amount, then the title and ring; a line still too wide breaks at word breaks. Nothing is cut.
    public func configure(with event: ChatRequestEvent, maxWidth: CGFloat) {
        let width = min(Self.textMaxWidth, maxWidth)
        captionWidth.constant = width
        let showsRing = event.ringFraction != nil && event.title != nil
        let ringRoom = Self.ringGap + Self.ringDiameter

        let first = Self.line(caption: event.caption, amount: event.amount, title: nil, separator: "")
        let whole = Self.line(caption: event.caption, amount: event.amount, title: event.title, separator: event.titleSeparator)
        let wraps = event.wraps(maxWidth: Double(width)) { includesTitle in
            Double(Self.width(of: includesTitle ? whole : first) + (includesTitle && showsRing ? ringRoom : 0))
        }

        ring.removeFromSuperview()
        lines.arrangedSubviews.forEach { $0.removeFromSuperview() }

        var rows: [(text: NSAttributedString, hasRing: Bool)] = []
        if wraps, let title = event.title {
            rows += Self.wrap(first, maxWidth: width, ring: false).map { ($0, false) }
            let titleRows = Self.wrap(Self.text(title, font: Self.font, color: Self.textColor), maxWidth: width, ring: showsRing)
            rows += titleRows.enumerated().map { ($1, showsRing && $0 == titleRows.count - 1) }
        } else {
            let wrapped = Self.wrap(whole, maxWidth: width, ring: showsRing)
            rows += wrapped.enumerated().map { ($1, showsRing && $0 == wrapped.count - 1) }
        }

        for row in rows {
            let label = UILabel()
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textAlignment = .center
            label.attributedText = row.text
            label.preferredMaxLayoutWidth = width - (row.hasRing ? ringRoom : 0)
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.lineHeight).isActive = true

            let line = UIStackView(arrangedSubviews: [label])
            line.axis = .horizontal
            line.alignment = .center
            line.spacing = Self.ringGap
            if row.hasRing, let fraction = event.ringFraction {
                line.addArrangedSubview(ring)
                // Keyed by row, so a recycled cell shows the new row's ring without sweeping to it.
                ring.configuration = UIHostingConfiguration { RequestEventRing(fraction: fraction, rowID: event.id) }
                    .margins(.all, 0)
            }
            lines.addArrangedSubview(line)
        }

        accessibilityLabel = event.spokenText
        accessibilityTraits = event.requestID == nil ? .staticText : [.staticText, .button]
    }

    /// `text` broken between words into lines that fit `maxWidth`, the last with room for the ring
    /// when `ring` is set.
    private static func wrap(_ text: NSAttributedString, maxWidth: CGFloat, ring: Bool) -> [NSAttributedString] {
        var words: [NSAttributedString] = []
        var start = 0
        let string = text.string as NSString
        for index in 0...string.length where index == string.length || string.character(at: index) == 0x20 {
            if index > start { words.append(text.attributedSubstring(from: NSRange(location: start, length: index - start))) }
            start = index + 1
        }
        let gap = ceil(" ".size(withAttributes: [.font: font]).width)
        let ranges = ChatRequestEvent.wrapLines(
            widths: words.map { Double(ceil($0.size().width)) },
            gap: Double(gap),
            maxWidth: Double(maxWidth),
            trailing: ring ? Double(ringGap + ringDiameter) : 0
        )
        return ranges.map { range in
            let line = NSMutableAttributedString()
            for index in range {
                if index > range.lowerBound { line.append(Self.text(" ", font: font, color: textColor)) }
                line.append(words[index])
            }
            return line
        }
    }

    /// One line of the row: the caption, the amount, and the title after `separator`.
    private static func line(caption: [ChatRequestEvent.Span], amount: String?, title: String?, separator: String) -> NSAttributedString {
        let line = NSMutableAttributedString()
        for span in caption {
            line.append(text(span.text, font: span.isEmphasized ? emphasisFont : font, color: textColor))
        }
        if let amount {
            line.append(text(" ", font: font, color: textColor))
            line.append(text(amount, font: emphasisFont, color: textColor))
        }
        if let title {
            line.append(text(separator + title, font: font, color: textColor))
        }
        return line
    }

    private static func text(_ string: String, font: UIFont, color: UIColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    private static func width(of line: NSAttributedString) -> CGFloat {
        ceil(line.size().width)
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
#endif
