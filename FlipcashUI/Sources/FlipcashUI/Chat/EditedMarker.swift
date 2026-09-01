//
//  EditedMarker.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// The "Edited" marker's type and placement, shared by both bubble kinds so they render it the
/// same way. WhatsApp puts the marker on the bubble's metadata line, flush to the trailing edge;
/// we have no per-bubble timestamp, so the marker takes that corner on its own — on the last line
/// of the body where there is room for it, on a line of its own where there isn't.
enum EditedMarker {

    static let text = "Edited"

    /// The receipt line's type and color, so the two pieces of bubble metadata read as one family
    /// rather than drifting apart. WhatsApp sets its marker at the timestamp's size, not the body's.
    static let font: UIFont = .default(size: 11, weight: .medium)
    static let color: UIColor = ChatReceiptView.defaultColor

    /// Inset from the bubble's trailing edge — the body's own inset, so the marker lines up with
    /// the text above it.
    static let trailingInset: CGFloat = 12

    /// The run appended to the body to hold the marker's place: the marker's own string in its own
    /// font, drawn in clear. Reserving with the real glyphs makes the gap exactly the width the
    /// overlaid label needs, and the leading spaces are breakable, so a last line with no room for
    /// the marker drops the reservation onto a new line instead of dragging the last word with it.
    static var reservation: NSAttributedString {
        NSAttributedString(
            string: "  \(text)",
            attributes: [.font: font, .foregroundColor: UIColor.clear]
        )
    }

    /// The label that draws the marker, to be pinned to the bubble's bottom-trailing corner.
    static func makeLabel() -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        // The body already carries the marker in its reservation run, so VoiceOver reads it in
        // place; this label would only repeat it.
        label.isAccessibilityElement = false
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
#endif
