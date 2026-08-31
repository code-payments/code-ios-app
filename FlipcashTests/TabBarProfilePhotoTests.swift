//
//  TabBarProfilePhotoTests.swift
//  FlipcashTests
//

import SwiftUI
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

    /// The unselected tab wears its own thinner, half-opacity ring rather than
    /// the selected ring dimmed, so the two differ at matched opacity too.
    @Test("The unselected icon wears a different ring, not just less opacity")
    func unselectedIconWearsItsOwnRing() throws {
        let photo = Self.photo(side: 64)

        let selected = try #require(Self.render(ProfileTabIcon(photo: photo, isSelected: true)))
        let unselected = try #require(Self.render(ProfileTabIcon(photo: photo, isSelected: false)))

        #expect(selected.pngData() != unselected.pngData())
    }

    /// A cold launch knows a picture exists before it has one to draw, and the
    /// slot has to hold the space regardless — an empty ring is still not the
    /// tip card's glyph.
    @Test("A slot with no picture yet still renders at the glyph slot size")
    func pendingRenditionsFillTheGlyphSlot() throws {
        let images = try #require(TabBarProfilePhoto.pendingItemImages(preview: nil))
        let slot = CGSize(width: ProfileTabIcon.slotSize, height: ProfileTabIcon.slotSize)

        #expect(images.normal.size == slot)
        #expect(images.selected.size == slot)
    }

    /// The pending renditions are read from a view body, so re-rendering them on
    /// every pass would put two `ImageRenderer` passes in the layout path.
    @Test("The same preview renders once and is reused")
    func pendingRenditionsAreMemoized() throws {
        let preview = Self.photo(side: 24)

        let first = try #require(TabBarProfilePhoto.pendingItemImages(preview: preview))
        let second = try #require(TabBarProfilePhoto.pendingItemImages(preview: preview))

        #expect(first.normal === second.normal)
        #expect(first.selected === second.selected)
    }

    /// `ProfileTabIcon` draws whatever the slot carries, so the BlurHash preview
    /// has to reach it by the same route the loaded photo does.
    @Test("A pending slot offers its BlurHash preview as the icon's picture")
    func pendingSlotCarriesItsPreview() throws {
        let preview = Self.photo(side: 24)

        #expect(ProfileTabSlot.pending(preview).preview === preview)
        #expect(ProfileTabSlot.pending(nil).preview == nil)
        #expect(ProfileTabSlot.photo(preview).preview === preview)
    }

    private static func render(_ icon: ProfileTabIcon) -> UIImage? {
        ImageRenderer(content: icon).uiImage
    }

    private static func photo(side: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}
