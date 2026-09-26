//
//  EmojiDrawability.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreText
import Foundation

/// Answers whether this OS draws an emoji as one Apple Color Emoji glyph cluster.
public enum EmojiDrawability {

    // CoreText documents font objects as immutable and safe to share across threads.
    nonisolated(unsafe) private static let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 32, nil)
    private static let unitWidth = CTLineGetTypographicBounds(line("😀"), nil, nil, nil)

    /// Returns whether this OS draws `emoji` as a single emoji.
    public static func isDrawable(_ emoji: String) -> Bool {
        probe(emoji)
    }

    // Drawable means every run is AppleColorEmoji, no glyph is 0 (the missing-glyph box), and the
    // line is no wider than one emoji. Counting glyphs is not a substitute: Apple's font draws some
    // supported sequences, such as mixed-skin-tone handshakes, from several overlapping glyphs.
    static func probe(_ emoji: String) -> Bool {
        let shaped = line(emoji)
        let runs = (CTLineGetGlyphRuns(shaped) as? [CTRun]) ?? []
        guard !runs.isEmpty else { return false }
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            // Swift rejects `as? CTFont`, so the CFTypeID check stands in for the conditional cast.
            guard let value = attributes[kCTFontAttributeName as String].map({ $0 as AnyObject }),
                  CFGetTypeID(value) == CTFontGetTypeID() else { return false }
            let runFont = value as! CTFont
            guard (CTFontCopyPostScriptName(runFont) as String) == "AppleColorEmoji" else { return false }
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            if glyphs.contains(0) { return false }
        }
        // An unsupported sequence falls apart into two or more emoji widths side by side.
        return CTLineGetTypographicBounds(shaped, nil, nil, nil) < unitWidth * 1.5
    }

    private static func line(_ string: String) -> CTLine {
        let attributed = NSAttributedString(
            string: string,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        return CTLineCreateWithAttributedString(attributed)
    }
}
