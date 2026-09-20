//
//  StillImageCodeSearch.swift
//  Flipcash
//

import CoreGraphics

/// The order in which a still image is searched for a Kik code.
///
/// A camera frame needs none of this: the user aims, so the code is roughly centred and
/// roughly the right size. A photo is whatever someone happened to capture, and
/// `KikCodes.scan` reads at a fixed scale, so a small code has to be cropped out and
/// scaled up before the scanner can see it.
///
/// Pure arithmetic, deliberately: the decoding half is slow and needs a device, and this
/// half is where the off-by-ones live.
///
/// The constants come from Code's `processBitmapRecursively` and `slidingWindowSearch`
/// (`f81d064d0`). They have never been measured against a corpus — see the spec's open
/// decisions.
///
/// `nonisolated` because the target defaults to `@MainActor` and the search that walks this
/// runs off the main actor — see ``GalleryScanner``.
nonisolated enum StillImageCodeSearch {

    struct Candidate: Equatable {
        /// In the image's own pixel coordinates.
        let rect: CGRect
        /// How much the crop is scaled up before scanning.
        let zoom: CGFloat
    }

    /// A quadrant is not subdivided below this, because a code smaller than this in the
    /// original is past the point where scaling recovers it.
    static let minimumSectionSize: CGFloat = 100

    static let zoomLevels: [CGFloat] = [1, 2, 5, 10]

    static let windowSize: CGFloat = 300
    static let windowStep: CGFloat = 150

    /// The longest side any crop is rendered at. This is what makes `zoom` mean something:
    /// a large crop has no room to grow and is scanned once, while a small one gets the
    /// whole ladder. Without the cap, zoom 10 on a half-frame quadrant would render a
    /// 9600-pixel buffer to look for a code that is already plainly visible.
    static let maximumRenderedSide: CGFloat = 1600

    /// Every crop the search will try, in the order it will try them.
    ///
    /// Tier 1 is the whole image, which is the only tier that runs for a screenshot where
    /// the code fills the frame. Tiers 2 and 3 are the expensive ones and exist for photos
    /// of a screen across a room.
    static func candidates(in size: CGSize) -> [Candidate] {
        let bounds = CGRect(origin: .zero, size: size)

        var candidates: [Candidate] = [Candidate(rect: bounds, zoom: 1)]
        var seen: Set<String> = [key(for: candidates[0])]

        appendSubdivisions(of: bounds, to: &candidates, seen: &seen)
        appendWindows(over: bounds, to: &candidates, seen: &seen)

        return candidates
    }

    // MARK: - Tiers -

    private static func appendSubdivisions(
        of rect: CGRect,
        to candidates: inout [Candidate],
        seen: inout Set<String>
    ) {
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2

        guard min(halfWidth, halfHeight) >= minimumSectionSize else {
            return
        }

        for row in 0..<2 {
            for column in 0..<2 {
                let quadrant = CGRect(
                    x: rect.minX + CGFloat(column) * halfWidth,
                    y: rect.minY + CGFloat(row) * halfHeight,
                    width: halfWidth,
                    height: halfHeight
                )

                append(quadrant, to: &candidates, seen: &seen)
                appendSubdivisions(of: quadrant, to: &candidates, seen: &seen)
            }
        }
    }

    private static func appendWindows(
        over bounds: CGRect,
        to candidates: inout [Candidate],
        seen: inout Set<String>
    ) {
        guard bounds.width >= windowSize, bounds.height >= windowSize else {
            return
        }

        var y: CGFloat = 0
        while y + windowSize <= bounds.height {
            var x: CGFloat = 0
            while x + windowSize <= bounds.width {
                append(
                    CGRect(x: x, y: y, width: windowSize, height: windowSize),
                    to: &candidates,
                    seen: &seen
                )
                x += windowStep
            }
            y += windowStep
        }
    }

    // MARK: - Helpers -

    /// Adds `rect` at every zoom that fits under ``maximumRenderedSide``, skipping any
    /// crop-and-zoom pair already enumerated by an earlier tier.
    private static func append(
        _ rect: CGRect,
        to candidates: inout [Candidate],
        seen: inout Set<String>
    ) {
        let longestSide = max(rect.width, rect.height)

        for zoom in zoomLevels where longestSide * zoom <= maximumRenderedSide {
            let candidate = Candidate(rect: rect, zoom: zoom)
            let key = key(for: candidate)

            guard !seen.contains(key) else { continue }

            seen.insert(key)
            candidates.append(candidate)
        }
    }

    private static func key(for candidate: Candidate) -> String {
        "\(candidate.rect.minX),\(candidate.rect.minY),\(candidate.rect.width),\(candidate.rect.height)@\(candidate.zoom)"
    }
}
