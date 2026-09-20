//
//  StillImageCodeSearchTests.swift
//  FlipcashTests
//

import CoreGraphics
import Testing

@testable import Flipcash

@Suite("Still Image Code Search")
struct StillImageCodeSearchTests {

    @Test("the first candidate is the whole image at zoom 1")
    func firstCandidateIsTheWholeImage() {
        let size = CGSize(width: 1920, height: 1080)
        let first = try! #require(StillImageCodeSearch.candidates(in: size).first)

        #expect(first.rect == CGRect(origin: .zero, size: size))
        #expect(first.zoom == 1)
    }

    @Test("every candidate lies inside the image")
    func everyCandidateIsInBounds() {
        let size = CGSize(width: 1920, height: 1080)
        let bounds = CGRect(origin: .zero, size: size)

        for candidate in StillImageCodeSearch.candidates(in: size) {
            #expect(bounds.contains(candidate.rect), "out of bounds: \(candidate.rect)")
        }
    }

    @Test("a crop is never rendered larger than the cap")
    func renderedSideIsCapped() {
        let size = CGSize(width: 1920, height: 1080)

        for candidate in StillImageCodeSearch.candidates(in: size) {
            let longest = max(candidate.rect.width, candidate.rect.height) * candidate.zoom
            // The whole image is exempt: tier 1 always runs whatever the image's size, so it
            // is appended before the cap prunes zoom levels, and `GalleryScanner` clamps its
            // rendered side instead. Every other candidate earns its place by fitting.
            #expect(
                longest <= StillImageCodeSearch.maximumRenderedSide
                    || candidate.rect.size == size,
                "\(candidate.rect) at zoom \(candidate.zoom) renders to \(longest)"
            )
        }
    }

    @Test("quadrants stop subdividing at the minimum section size")
    func quadrantsStopAtMinimumSectionSize() {
        let size = CGSize(width: 1920, height: 1080)

        for candidate in StillImageCodeSearch.candidates(in: size) {
            let shortest = min(candidate.rect.width, candidate.rect.height)
            #expect(
                shortest >= StillImageCodeSearch.minimumSectionSize
                    || candidate.rect.size == size,
                "section too small: \(candidate.rect)"
            )
        }
    }

    @Test("the same crop is never enumerated twice at the same zoom")
    func candidatesAreDistinct() {
        let candidates = StillImageCodeSearch.candidates(in: CGSize(width: 1920, height: 1080))
        let keys = candidates.map { "\($0.rect)@\($0.zoom)" }

        #expect(Set(keys).count == keys.count, "duplicate candidates in the ladder")
    }

    @Test("an image smaller than one window still yields the whole image")
    func tinyImageYieldsWholeImage() {
        let size = CGSize(width: 80, height: 60)
        let candidates = StillImageCodeSearch.candidates(in: size)

        #expect(candidates.count >= 1)
        #expect(candidates.first?.rect == CGRect(origin: .zero, size: size))
    }
}
