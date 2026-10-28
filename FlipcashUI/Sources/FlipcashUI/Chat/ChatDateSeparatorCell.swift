//
//  ChatDateSeparatorCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

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
        label.attributedText = Self.styled(text) // LOCAL-TUNER
    }

    // LOCAL-TUNER: the day ("Oct 20", "Today") and the time ("15:40") set apart, each in its own type.
    static func styled(_ text: String) -> NSAttributedString { // LOCAL-TUNER
        let dayFont = UIFont.default(size: Tuner.value("Chat v2 Date/Day size", default: 12, in: 9...17, unit: .points), weight: Tuner.value("Chat v2 Date/Day weight", default: ChatTextWeight.medium).weight) // LOCAL-TUNER
        let timeFont = UIFont.default(size: Tuner.value("Chat v2 Date/Time size", default: 12, in: 9...17, unit: .points), weight: Tuner.value("Chat v2 Date/Time weight", default: ChatTextWeight.regular).weight) // LOCAL-TUNER
        let dayColor = UIColor(Tuner.value("Chat v2 Date/Day color", default: Color.white.opacity(0.5))) // LOCAL-TUNER
        let timeColor = UIColor(Tuner.value("Chat v2 Date/Time color", default: Color.white.opacity(0.5))) // LOCAL-TUNER
        let gap = Tuner.value("Chat v2 Date/Gap", default: 4, in: 0...16, unit: .points) // LOCAL-TUNER
        guard let match = text.range(of: #"\d{1,2}[:.]\d{2}.*$"#, options: .regularExpression), match.lowerBound > text.startIndex else { // LOCAL-TUNER
            return NSAttributedString(string: text, attributes: [.font: timeFont, .foregroundColor: timeColor]) // LOCAL-TUNER
        } // LOCAL-TUNER
        let day = text[..<match.lowerBound].trimmingCharacters(in: .whitespaces) // LOCAL-TUNER
        let result = NSMutableAttributedString(string: day, attributes: [.font: dayFont, .foregroundColor: dayColor, .kern: gap]) // LOCAL-TUNER
        result.append(NSAttributedString(string: String(text[match]), attributes: [.font: timeFont, .foregroundColor: timeColor])) // LOCAL-TUNER
        if let last = day.indices.last { result.addAttribute(.kern, value: 0, range: NSRange(..<last, in: day)) } // LOCAL-TUNER
        return result // LOCAL-TUNER
    } // LOCAL-TUNER
}
#endif
