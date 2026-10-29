//
//  ChatDateSeparatorCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// A centered day + time header between runs of messages (e.g. "Today 12:13 PM"). Dumb — it
/// renders the already-formatted string it's handed.
public final class ChatDateSeparatorCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatDateSeparatorCell"

    private let label = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .default(size: 12, weight: .bold)
        label.textColor = UIColor.white.withAlphaComponent(0.5)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(text: String) {
        label.attributedText = Self.styled(text)
    }

    /// The day ("Oct 20", "Today") and the time ("15:40") set apart, each in its own type.
    private static func styled(_ text: String) -> NSAttributedString {
        let dayFont = UIFont.default(size: 12, weight: .medium)
        let timeFont = UIFont.default(size: 12, weight: .regular)
        let color = UIColor.white.withAlphaComponent(0.5)
        guard let match = text.range(of: #"\d{1,2}[:.]\d{2}.*$"#, options: .regularExpression), match.lowerBound > text.startIndex else {
            return NSAttributedString(string: text, attributes: [.font: timeFont, .foregroundColor: color])
        }
        // The day keeps its trailing space, so VoiceOver reads "Oct 20 15:40", not "Oct 2015:40".
        let day = String(text[..<match.lowerBound])
        let result = NSMutableAttributedString(string: day, attributes: [.font: dayFont, .foregroundColor: color])
        result.append(NSAttributedString(string: String(text[match]), attributes: [.font: timeFont, .foregroundColor: color]))
        return result
    }
}
#endif
