//
//  TabBarProfilePhotoTests.swift
//  FlipcashTests
//

import UIKit
import Testing
@testable import Flipcash

@MainActor
@Suite("Tab Bar Profile Photo Tests")
struct TabBarProfilePhotoTests {

    /// The photo replaces a glyph in a fixed slot, so a rendition of any other
    /// size would push the You tab's icon out of line with its neighbours.
    @Test("The rendered icons fill the glyph slot")
    func renditionsMatchTheGlyphSlot() throws {
        let images = try #require(TabBarProfilePhoto.render(Self.photo(side: 64)))
        let slot = CGSize(width: ProfileTabIcon.slotSize, height: ProfileTabIcon.slotSize)

        #expect(images.normal.size == slot)
        #expect(images.selected.size == slot)
    }

    /// The bar tints template glyphs to dim the unselected ones, and leaves an
    /// original-rendered photo alone — so the dimming has to be in the bytes.
    @Test("The unselected rendition is dimmed rather than left identical")
    func unselectedRenditionIsDimmed() throws {
        let images = try #require(TabBarProfilePhoto.render(Self.photo(side: 64)))

        #expect(images.normal.pngData() != images.selected.pngData())
    }

    private static func photo(side: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}
