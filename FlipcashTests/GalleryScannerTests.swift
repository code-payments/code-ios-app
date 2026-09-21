//
//  GalleryScannerTests.swift
//  FlipcashTests
//

import CoreGraphics
import CoreImage
import SwiftUI
import Testing
import UIKit

import CodeScanner
import FlipcashCore
@testable import Flipcash
@testable import FlipcashUI

/// The still-image half of the scanner harness. `CodeScanSweepTests` covers the camera
/// path; this covers the path a picked photo takes, which shares the decoder and nothing
/// else.
@MainActor
@Suite("Gallery Scanner")
struct GalleryScannerTests {

    /// A real cash payload rather than 20 arbitrary bytes: `ScannedCode` dispatches on the
    /// leading kind byte, so bytes that are not a cash or tip code decode from the image and
    /// then fail to parse — indistinguishable, from the scanner's outside, from finding nothing.
    static let payload = CashCode.Payload(
        kind: .cash,
        fiat: FiatAmount(value: 5, currency: .usd),
        nonce: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x10])
    ).encode()

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

    // MARK: - Decoding -

    @Test("a code filling the frame decodes on the first tier")
    func fullFrameCodeDecodes() async throws {
        let image = try Self.makeImage(size: CGSize(width: 1200, height: 1200), codeSide: 1000)

        let outcome = await GalleryScanner().scan(image)

        guard case .code(let code, _) = outcome else {
            Issue.record("expected a code, got \(outcome)")
            return
        }

        switch code {
        case .cash, .tip:
            break
        }
    }

    @Test("a small off-centre code decodes from a later tier")
    func smallOffCentreCodeDecodes() async throws {
        let image = try Self.makeImage(
            size: CGSize(width: 1600, height: 1200),
            codeSide: 260,
            origin: CGPoint(x: 120, y: 700)
        )

        let outcome = await GalleryScanner().scan(image)

        guard case .code = outcome else {
            Issue.record("expected a code, got \(outcome)")
            return
        }
    }

    @Test("an image with no code reports nothing found")
    func emptyImageFindsNothing() async throws {
        // Screenshot-sized rather than token-sized: the distinction between running out of
        // crops and running out of time only means anything if a real image can run out of
        // crops first, and 517 of them inside the budget is the claim being made.
        let image = try Self.makeSolidImage(color: .darkGray, size: CGSize(width: 1179, height: 2556))

        // Explicit and generous rather than the shipping budget: the claim is that the ladder
        // ends on its own, and leaving it on the default turns the result into a statement
        // about how fast the machine is. On CI the default expires first and this reads
        // `.cancelled` — the one outcome the test exists to tell apart from `.nothingFound`.
        let outcome = await GalleryScanner().scan(image, budget: 120)

        guard case .nothingFound = outcome else {
            Issue.record("expected nothing found, got \(outcome)")
            return
        }
    }

    @Test("the budget is respected when there is nothing to find")
    func budgetIsRespected() async throws {
        // A full 12 MP frame, so the deadline is what ends the search rather than the ladder
        // running out. Its 2338 crops take seconds even spread across every core.
        let image = try Self.makeSolidImage(color: .darkGray, size: CGSize(width: 3024, height: 4032))

        let started = Date()
        let outcome = await GalleryScanner().scan(image, budget: 0.5)
        let elapsed = Date().timeIntervalSince(started)

        guard case .cancelled = outcome else {
            Issue.record("expected the budget to end the search, got \(outcome)")
            return
        }
        // One crop may overrun the deadline, since the budget is checked between candidates
        // rather than inside the native scanner. The margin is for that, not for slack.
        #expect(elapsed < 2.0, "budget of 0.5s took \(elapsed)s")
    }

    @Test("a cancelled scan stops without a result")
    func cancellationStopsTheSearch() async throws {
        let image = try Self.makeSolidImage(color: .darkGray, size: CGSize(width: 2400, height: 1800))

        let task = Task { await GalleryScanner().scan(image) }
        task.cancel()

        guard case .cancelled = await task.value else {
            Issue.record("expected cancellation")
            return
        }
    }

    @Test("a QR code decodes without waiting for the Kik ladder")
    func qrCodeDecodes() async throws {
        // Deliberately large: the QR pass and the crops race, and on an image this size the
        // crops take seconds. Timing it is the only way to tell a race from a queue — with
        // the QR pass behind the ladder this would still return the right URL, just far
        // later than anyone would hold a phone still for.
        let image = try Self.makeQRImage(
            string: "https://send.flipcash.com/c/#/e=abc",
            size: CGSize(width: 2400, height: 2400)
        )

        let started = Date()
        let outcome = await GalleryScanner().scan(image)
        let elapsed = Date().timeIntervalSince(started)

        guard case .url(let url) = outcome else {
            Issue.record("expected a URL, got \(outcome)")
            return
        }
        #expect(url == URL(string: "https://send.flipcash.com/c/#/e=abc")!)
        #expect(elapsed < 3, "QR took \(elapsed)s, which is the ladder's time, not the QR pass's")
    }

    @Test("the scanner reports a login URL and the allowlist refuses it")
    func loginQrIsRefusedByTheAllowlist() async throws {
        // The scanner's job is to report what it saw; refusing it is `canScanQR`'s. Asserted
        // as two steps because that separation is what lets one allowlist serve the camera,
        // the gallery, and the share sheet.
        let image = try Self.makeQRImage(
            string: "https://send.flipcash.com/login/#/e=abc",
            size: CGSize(width: 800, height: 800)
        )

        guard case .url(let url) = await GalleryScanner().scan(image) else {
            Issue.record("expected the QR to decode")
            return
        }

        #expect(ScanViewModel.canScanQR(url: url) == false)
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

    /// A QR code rendered dark-on-light, which is the polarity `CIQRCodeGenerator`
    /// produces and the polarity Vision expects.
    static func makeQRImage(string: String, size: CGSize) throws -> CGImage {
        guard
            let filter = CIFilter(name: "CIQRCodeGenerator"),
            let data = string.data(using: .utf8)
        else {
            throw Failure.renderFailed
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else {
            throw Failure.renderFailed
        }

        let scale = min(size.width / output.extent.width, size.height / output.extent.height)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else {
            throw Failure.renderFailed
        }
        return cgImage
    }

    enum Failure: Error {
        case renderFailed
    }
}
