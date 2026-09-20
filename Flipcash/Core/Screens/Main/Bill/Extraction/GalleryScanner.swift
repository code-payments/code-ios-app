//
//  GalleryScanner.swift
//  Flipcash
//

import CoreGraphics
import CoreImage
import Foundation
import Vision

import CodeScanner
import FlipcashCore
import FlipcashUI

nonisolated private let logger = Logger(label: "flipcash.scan.gallery")

/// Searches a still image for something the scanner understands.
///
/// The camera path in ``CodeExtractor`` sees a code because the user aimed at one. Here the
/// image is whatever was picked, so the Kik search has to crop and scale its way across it
/// — see ``StillImageCodeSearch``. QR needs none of that: `VNDetectBarcodesRequest` scales
/// internally, which is why it is one pass at the end rather than a tier of its own.
///
/// Kik runs first, matching the camera's detector order in Android's
/// `rememberMultiCodeAnalyzer` (`listOf(kikCodeAnalyzer, qrCodeAnalyzer)`).
///
/// `nonisolated` because the target defaults to `@MainActor`, and a search that renders and
/// decodes dozens of crops must not run there — see ``scan(_:budget:)``.
nonisolated struct GalleryScanner {

    /// Not `Equatable`: `ScannedCode` carries payload types that are not, and the one place
    /// that wants equality is a test asserting a non-code outcome, which pattern-matches.
    enum Outcome {
        case code(ScannedCode)
        case url(URL)
        case nothingFound
        /// The budget ran out, or the caller cancelled. Reported the same way as
        /// `nothingFound` in the UI; kept apart here so the tests can tell them apart.
        case cancelled
    }

    /// How long the whole search may take. Long enough that no successful search has ever
    /// hit it, short enough that a photo of a wall gives up. A guess, not a measurement —
    /// see the spec's open decisions.
    static let budget: TimeInterval = 8.0

    /// Searches `image`, giving up after `budget` seconds or on cancellation.
    ///
    /// `@concurrent` rather than plain `nonisolated`: the target builds with
    /// `nonisolated(nonsending)` by default, so without it the whole ladder would run on the
    /// caller's actor — the main one — and the spinner it blocks is the spinner whose Cancel
    /// button ends the search.
    @concurrent
    func scan(_ image: CGImage, budget: TimeInterval = GalleryScanner.budget) async -> Outcome {
        let deadline = Date().addingTimeInterval(budget)
        let size = CGSize(width: image.width, height: image.height)

        var exhausted = true

        for candidate in StillImageCodeSearch.candidates(in: size) {
            if Task.isCancelled || Date() >= deadline {
                exhausted = false
                break
            }

            let renderedSide = min(
                max(candidate.rect.width, candidate.rect.height) * candidate.zoom,
                StillImageCodeSearch.maximumRenderedSide
            )

            guard
                let sample = CodeExtractor.luminanceSample(
                    from: image,
                    crop: candidate.rect,
                    renderedSide: renderedSide
                )
            else {
                continue
            }

            if let code = Self.decode(sample) {
                logger.debug("Kik code found in still image", metadata: [
                    "crop": "\(candidate.rect)",
                    "zoom": "\(candidate.zoom)",
                ])
                return .code(code)
            }
        }

        if Task.isCancelled {
            return .cancelled
        }

        if let url = Self.detectQR(in: image) {
            return .url(url)
        }

        return exhausted ? .nothingFound : .cancelled
    }

    // MARK: - Kik -

    private static func decode(_ sample: CodeExtractor.Sample) -> ScannedCode? {
        guard
            let scanned = KikCodes.scan(
                sample.data,
                width: sample.width,
                height: sample.height,
                quality: .best
            )
        else {
            return nil
        }

        return ScannedCode(data: KikCodes.decode(scanned))
    }

    // MARK: - QR -

    /// The first QR payload in the image that parses as a URL.
    ///
    /// Route eligibility is not decided here — that is ``ScanViewModel/canScanQR(url:)``,
    /// so the gallery, the camera, and the share sheet all answer to one allowlist.
    private static func detectQR(in image: CGImage) -> URL? {
        let payloads = visionPayloads(in: image) ?? detectorPayloads(in: image)
        return payloads.lazy.compactMap { URL(string: $0) }.first
    }

    /// Vision's read, or `nil` when Vision could not run at all — an empty array means it
    /// ran and saw no QR, which is an answer and needs no second opinion.
    private static func visionPayloads(in image: CGImage) -> [String]? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            logger.debug("Vision barcode detection unavailable", metadata: ["error": "\(error)"])
            return nil
        }

        return (request.results ?? []).compactMap { $0.payloadStringValue }
    }

    /// The fallback for when Vision cannot start: weaker on codes that are small or at an
    /// angle, but it needs no inference context, which is the one thing Vision cannot get on
    /// the simulator. Without it every QR test here would be testing the failure path.
    private static func detectorPayloads(in image: CGImage) -> [String] {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )

        let features = detector?.features(in: CIImage(cgImage: image)) as? [CIQRCodeFeature]
        return features?.compactMap { $0.messageString } ?? []
    }
}
