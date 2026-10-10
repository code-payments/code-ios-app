//
//  ChatTextStyling.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// Draws the parser's spans onto a bubble's text. The text already has the bubble's base font and
/// colour; this adds weight, slant, strike, monospace, and the indents that block styles take.
enum ChatTextStyling {

    /// Set over each quoted line; the text view draws one bar down each run of them.
    static let quoteBar = NSAttributedString.Key("flipcash.quoteBar")

    static let codeBackground = UIColor.white.withAlphaComponent(0.12)
    static let quoteBarWidth: CGFloat = 3
    static let quoteIndent: CGFloat = 12
    static let bulletIndent: CGFloat = 12
    static let numberedIndent: CGFloat = 20

    static func apply(_ spans: [ChatTextSpan], to text: NSMutableAttributedString, size: CGFloat, weight: UIFont.Weight) {
        let length = text.length
        guard length > 0, !spans.isEmpty else { return }
        let bounds = NSRange(location: 0, length: length)
        func clamped(_ span: ChatTextSpan) -> NSRange? {
            let range = NSIntersectionRange(span.range, bounds)
            return range.length > 0 ? range : nil
        }

        // Weight and slant combine, so they are worked out per character and applied as runs.
        var bold = [Bool](repeating: false, count: length)
        var italic = bold
        for span in spans {
            guard let range = clamped(span) else { continue }
            switch span.style {
            case .bold: for index in range.location..<NSMaxRange(range) { bold[index] = true }
            case .italic: for index in range.location..<NSMaxRange(range) { italic[index] = true }
            case .strike:
                text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .code, .codeBlock, .quote, .bullet, .numbered:
                break
            }
        }
        var start = 0
        while start < length {
            var end = start + 1
            while end < length, bold[end] == bold[start], italic[end] == italic[start] { end += 1 }
            if bold[start] || italic[start] {
                let face: UIFont.Weight = bold[start] ? .bold : weight
                let font: UIFont = italic[start]
                    ? .defaultOblique(size: size, weight: face)
                    : .default(size: size, weight: face)
                text.addAttribute(.font, value: font, range: NSRange(location: start, length: end - start))
            }
            start = end
        }

        for span in spans {
            guard let range = clamped(span) else { continue }
            switch span.style {
            case .code, .codeBlock:
                text.addAttributes([.font: UIFont.roboto(size: size - 1), .backgroundColor: codeBackground], range: range)
            case .quote:
                text.addAttribute(quoteBar, value: true, range: range)
            case .bold, .italic, .strike, .bullet, .numbered:
                break
            }
        }

        applyIndents(spans, to: text)
    }

    /// One paragraph style per line a block style touches: a quote leaves the gutter for its bar, a
    /// list item hangs its wrapped lines past the marker. The marker characters stay in the text.
    private static func applyIndents(_ spans: [ChatTextSpan], to text: NSMutableAttributedString) {
        struct Line { var quoted = false; var hang: CGFloat = 0 }
        let string = text.string as NSString
        var lines: [Int: (range: NSRange, line: Line)] = [:]
        for span in spans {
            let isBlock = switch span.style {
            case .quote, .bullet, .numbered: true
            case .bold, .italic, .strike, .code, .codeBlock: false
            }
            guard isBlock, NSMaxRange(span.range) <= string.length, span.length > 0 else { continue }
            var location = span.location
            while location < NSMaxRange(span.range) {
                let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
                var entry = lines[paragraph.location] ?? (paragraph, Line())
                switch span.style {
                case .quote: entry.line.quoted = true
                case .bullet: entry.line.hang = bulletIndent
                case .numbered: entry.line.hang = numberedIndent
                case .bold, .italic, .strike, .code, .codeBlock: break
                }
                lines[paragraph.location] = entry
                location = NSMaxRange(paragraph)
            }
        }
        for (range, line) in lines.values {
            let style = NSMutableParagraphStyle()
            let lead = line.quoted ? quoteIndent : 0
            style.firstLineHeadIndent = lead
            style.headIndent = lead + line.hang
            text.addAttribute(.paragraphStyle, value: style, range: range)
        }
    }
}
#endif
