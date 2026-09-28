//
//  ComposerChipLayoutTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
@testable import Flipcash

@MainActor
@Suite("Composer chip layout")
struct ComposerChipLayoutTests {

    @Test("A portrait photo's chip stays inside its square, clear of the row below")
    func portraitChip_staysInsideItsSquare() async throws {
        let host = try AttachPanelHost()
        defer { host.tearDown() }
        await host.settle()

        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 400)).image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
        }
        host.composer.stageChip(image: portrait, preview: portrait, uploader: ChatMediaUploader(blob: MockChatMediaBlobStore()))
        await host.settle()

        // Down the chip's leading quarter, clear of the centred badge and the trailing remove button.
        // The strip sits inside the field, which starts past `+`. Before the fix the photo filled at
        // its own aspect and spilled past the 56pt square, over the text row below it.
        let chipLeading = try #require(
            stride(from: CGFloat(0), to: host.window.bounds.width, by: 2).first { x in
                host.renderedColumn(atX: x, backdrop: .black).contains { $0.isGreenDominant }
            },
            "The chip was not drawn"
        )
        let column = host.renderedColumn(atX: chipLeading + 12, backdrop: .black)
        let greenRows = column.filter { $0.isGreenDominant }.count
        #expect(greenRows > 0, "The chip was not drawn")
        #expect(greenRows <= Int(ComposerChipStrip.chipSize) + 1, "The chip is \(greenRows)pt tall")
    }
}

private extension AttachPanelHost {

    /// The window's rendered colours down the column at `x`, one per point.
    func renderedColumn(atX x: CGFloat, backdrop: UIColor) -> [UIColor] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { ctx in
            backdrop.setFill()
            ctx.fill(window.bounds)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cg = image.cgImage!
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: height * 4)
        let context = CGContext(
            data: &pixels, width: 1, height: height, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cg, in: CGRect(x: -x, y: 0, width: CGFloat(cg.width), height: CGFloat(height)))
        return (0..<height).map { row in
            let i = row * 4
            return UIColor(red: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255, blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
        }
    }
}

private extension UIColor {

    /// Whether this reads as the test photo's green, under the chip's badge dimming or not.
    var isGreenDominant: Bool {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return g > 0.35 && g > r * 2 && g > b * 2
    }
}
