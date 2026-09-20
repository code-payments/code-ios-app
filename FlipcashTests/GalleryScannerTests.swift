//
//  GalleryScannerTests.swift
//  FlipcashTests
//

import CoreGraphics
import SwiftUI
import Testing
import UIKit

import CodeScanner
@testable import Flipcash
@testable import FlipcashUI

/// The still-image half of the scanner harness. `CodeScanSweepTests` covers the camera
/// path; this covers the path a picked photo takes, which shares the decoder and nothing
/// else.
@MainActor
@Suite("Gallery Scanner")
struct GalleryScannerTests {

    /// `kikCodeEncodeRemote` takes a 20-byte payload.
    static let payload = Data((0..<20).map { UInt8(($0 &* 7 &+ 11) % 251) })

    // MARK: - Luminance -

    @Test("a rendered crop is tightly packed at the requested size")
    func luminanceSampleIsTightlyPacked() throws {
        let image = try Self.makeImage(size: CGSize(width: 800, height: 600), codeSide: 400)
        let sample = try #require(
            CodeExtractor.luminanceSample(
                from: image,
                crop: CGRect(x: 100, y: 100, width: 400, height: 400),
                renderedSide: 400
            )
        )

        #expect(sample.width == 400)
        #expect(sample.height == 400)
        #expect(sample.data.count == 400 * 400)
    }

    @Test("luminance uses the integer BT.601 form Android uses")
    func luminanceMatchesTheSharedRule() throws {
        // A flat mid-blue field: BT.601 gives (77*0 + 150*0 + 29*255) >> 8 == 28.
        let image = try Self.makeSolidImage(
            color: UIColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 16, height: 16)
        )
        let sample = try #require(
            CodeExtractor.luminanceSample(
                from: image,
                crop: CGRect(x: 0, y: 0, width: 16, height: 16),
                renderedSide: 16
            )
        )

        #expect(sample.data.allSatisfy { $0 == 28 }, "expected BT.601 luma of 28 for pure blue")
    }

    // MARK: - Helpers -

    /// A code rendered centred on a dark field. Polarity matches `CodeScanSweepTests`:
    /// light marks on dark, because the detector finds the centre badge by thresholding
    /// for bright blobs.
    static func makeImage(size: CGSize, codeSide: CGFloat, origin: CGPoint? = nil) throws -> CGImage {
        let encoded = KikCodes.encode(payload)

        let renderer = ImageRenderer(
            content: CodeView(data: encoded)
                .foregroundStyle(.white)
                .frame(width: codeSide, height: codeSide)
                .background(Color.black)
        )
        renderer.scale = 1.0

        guard let code = renderer.uiImage else {
            throw Failure.renderFailed
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0

        let composed = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let point = origin ?? CGPoint(
                x: (size.width - codeSide) / 2,
                y: (size.height - codeSide) / 2
            )
            code.draw(in: CGRect(origin: point, size: CGSize(width: codeSide, height: codeSide)))
        }

        guard let cgImage = composed.cgImage else {
            throw Failure.renderFailed
        }
        return cgImage
    }

    static func makeSolidImage(color: UIColor, size: CGSize) throws -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0

        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        guard let cgImage = image.cgImage else {
            throw Failure.renderFailed
        }
        return cgImage
    }

    enum Failure: Error {
        case renderFailed
    }
}
