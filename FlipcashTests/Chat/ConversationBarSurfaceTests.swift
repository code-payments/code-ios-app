//
//  ConversationBarSurfaceTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import SwiftUI
import UIKit
@testable import Flipcash

/// The composer bar's surface, which has one job the eye notices when it is missed: being opaque
/// everywhere a control sits on it.
///
/// The field is Liquid Glass, so it shows whatever the surface behind it still lets through. A ramp
/// that is only part way up at the field's top edge puts the transcript inside the field — a bubble
/// scrolling under the bar reads straight through the placeholder. So the ramp has to be finished
/// before the controls start, and these tests pin that down at the constant and at the pixel.
@MainActor
@Suite("Composer bar surface")
struct ConversationBarSurfaceTests {

    @Test("The ramp is finished before the controls start")
    func rampEndsAboveControls() {
        #expect(BarSurface.fadeHeight <= BarMetrics.contentPadding)
    }

    @Test("The surface is fully opaque from the controls' top edge down")
    func surfaceIsOpaqueBehindControls() throws {
        let alpha = try alphaByRow(height: BarMetrics.contentPadding + BarMetrics.contentHeight)
        for row in Int(BarMetrics.contentPadding.rounded(.up))..<alpha.count {
            #expect(alpha[row] == 1, "row \(row) is \(alpha[row]), not opaque")
        }
    }

    @Test("The top edge is a ramp, not a line")
    func topEdgeRamps() throws {
        let alpha = try alphaByRow(height: BarMetrics.contentPadding + BarMetrics.contentHeight)
        #expect(alpha[0] < 0.25)
        // Every row at least as opaque as the one above it, so the dissolve never steps backwards.
        for row in 1..<Int(BarMetrics.contentPadding) {
            #expect(alpha[row] >= alpha[row - 1])
        }
    }

    /// The surface's alpha down one column, one entry per point from its top edge.
    private func alphaByRow(height: CGFloat) throws -> [CGFloat] {
        let renderer = ImageRenderer(content: BarSurface.restingFade.frame(width: 4, height: height))
        // Point-for-pixel, so a row index is a distance from the top edge in points.
        renderer.scale = 1
        renderer.isOpaque = false
        let image = try #require(renderer.cgImage)

        let width = image.width
        var pixels = [UInt8](repeating: 0, count: width * image.height * 4)
        let context = try #require(
            CGContext(
                data: &pixels,
                width: width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: image.height))
        // Row 0 of a bitmap context's buffer is the top of what was drawn into it.
        return (0..<image.height).map { CGFloat(pixels[$0 * width * 4 + 3]) / 255 }
    }
}
