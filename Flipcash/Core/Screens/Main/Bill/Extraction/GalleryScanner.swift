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
/// internally, which is why it is one pass rather than a tier of its own.
///
/// The order is: the whole image as a Kik code, then everything else at once. Tier 1 is a
/// single crop and it is the one a screenshot of a bill hits, so it runs alone and a hit
/// there costs nothing else. After that the remaining crops and the QR pass race, because
/// the alternative — the full ladder, then QR — makes a picked QR wait out the entire
/// budget for a pass that takes a fraction of a second.
///
/// `nonisolated` because the target defaults to `@MainActor`, and a search that renders and
/// decodes hundreds of crops must not run there — see ``scan(_:budget:)``.
nonisolated struct GalleryScanner {

    /// Not `Equatable`: `ScannedCode` carries payload types that are not, and the one place
    /// that wants equality is a test asserting a non-code outcome, which pattern-matches.
    /// Where in the ladder a Kik code turned up. The caller times the search; this says
    /// what the time bought.
    ///
    /// Approximate past tier 1: the crops are searched in parallel, so this is the first
    /// hit reported rather than strictly the shallowest. Close enough to tell a screenshot
    /// from a photo of a screen across a room, which is what it is for.
    struct Match {
        let tier: StillImageCodeSearch.Tier
        let zoom: CGFloat
    }

    enum Outcome {
        case code(ScannedCode, Match)
        case url(URL)
        case nothingFound
        /// The budget ran out, or the caller cancelled. Reported the same way as
        /// `nothingFound` in the UI; kept apart here so the tests can tell them apart.
        case cancelled
    }

    /// How long the whole search may take. Long enough that no successful search has ever
    /// hit it, short enough that a photo of a wall gives up. A guess, not a measurement —
    /// see the spec's open decisions.
    ///
    /// It bounds the crops. The QR pass is a single uninterruptible call that runs outside
    /// it, which is why that pass reads a downscaled copy — see ``maximumQRSide``.
    static let budget: TimeInterval = 8.0

    /// The longest side the QR pass sees.
    ///
    /// Both detectors scale internally, but from whatever they are handed: on a 12 MP frame
    /// that cost is seconds, and `race` cannot return until the pass finishes, so it lands
    /// outside the deadline ``walk(_:from:by:of:until:)`` honours. A 0.5s budget measured
    /// 21s that way. Matching the ladder's own cap keeps a picked QR readable — a code too
    /// small to survive this is also too small for the ladder to have found.
    static let maximumQRSide: CGFloat = StillImageCodeSearch.maximumRenderedSide

    /// How many crops are rendered at once.
    ///
    /// One short of the cores, so the main actor still has somewhere to draw the spinner
    /// whose Cancel button ends this, and capped because each worker holds a render buffer
    /// of up to 10 MB.
    static var workerCount: Int {
        min(max(ProcessInfo.processInfo.activeProcessorCount - 1, 1), 6)
    }

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
        let candidates = StillImageCodeSearch.candidates(in: size)

        let wholeImage = candidates.prefix { $0.tier == .wholeImage }

        switch Self.walk(Array(wholeImage), of: image, until: deadline) {
        case .found(let code, let match):
            return .code(code, match)
        case .stopped:
            return .cancelled
        case .url, .nothing:
            break
        }

        return await Self.race(
            Array(candidates.dropFirst(wholeImage.count)),
            in: image,
            until: deadline
        )
    }

    // MARK: - Search -

    /// What one task came back with.
    private enum Finding {
        case found(ScannedCode, Match)
        case url(URL)
        /// Ran to the end and found nothing, which is an answer.
        case nothing
        /// Gave up on the deadline or on cancellation, so nothing found is not an answer.
        case stopped
    }

    /// The remaining crops and the QR pass, running against each other, first answer wins.
    ///
    /// A picked image holds a Kik code or a QR, effectively never both, so which would win a
    /// tie is not worth the wait it would cost to settle: awaiting the crops before reading
    /// the QR result would hold every QR screenshot for the length of the ladder.
    private static func race(
        _ candidates: [StillImageCodeSearch.Candidate],
        in image: CGImage,
        until deadline: Date
    ) async -> Outcome {
        await withTaskGroup(of: Finding.self) { group in
            group.addTask {
                detectQR(in: image).map { Finding.url($0) } ?? .nothing
            }

            let workers = workerCount
            for stripe in 0..<workers {
                group.addTask {
                    walk(candidates, from: stripe, by: workers, of: image, until: deadline)
                }
            }

            var stopped = false

            for await finding in group {
                switch finding {
                case .found(let code, let match):
                    group.cancelAll()
                    return .code(code, match)
                case .url(let url):
                    group.cancelAll()
                    return .url(url)
                case .stopped:
                    stopped = true
                case .nothing:
                    break
                }
            }

            return stopped ? .cancelled : .nothingFound
        }
    }

    /// Renders and decodes every `step`th candidate from `offset`.
    ///
    /// Striding rather than taking a contiguous slice each: the ladder is ordered cheapest
    /// and likeliest first, and a worker given the tail of it would spend the whole budget
    /// on the crops least likely to hold anything.
    ///
    /// One renderer for the whole walk, so the buffer is allocated once rather than per crop.
    private static func walk(
        _ candidates: [StillImageCodeSearch.Candidate],
        from offset: Int = 0,
        by step: Int = 1,
        of image: CGImage,
        until deadline: Date
    ) -> Finding {
        let renderer = StillImageLuminanceRenderer()
        var index = offset

        while index < candidates.count {
            if Task.isCancelled || Date() >= deadline {
                return .stopped
            }

            let candidate = candidates[index]
            index += step

            let renderedSide = min(
                max(candidate.rect.width, candidate.rect.height) * candidate.zoom,
                StillImageCodeSearch.maximumRenderedSide
            )

            guard
                let sample = renderer.sample(
                    from: image,
                    crop: candidate.rect,
                    renderedSide: renderedSide
                )
            else {
                continue
            }

            if let code = decode(sample) {
                logger.debug("Kik code found in still image", metadata: [
                    "crop": "\(candidate.rect)",
                    "zoom": "\(candidate.zoom)",
                    "tier": "\(candidate.tier.rawValue)",
                ])
                return .found(code, Match(tier: candidate.tier, zoom: candidate.zoom))
            }
        }

        return .nothing
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
        let scaled = downscaled(image, to: maximumQRSide)
        let vision = visionPayloads(in: scaled) ?? []
        let payloads = vision.isEmpty ? detectorPayloads(in: scaled) : vision
        return payloads.lazy.compactMap { URL(string: $0) }.first
    }

    /// `image` with its longest side brought down to `maximumSide`, or `image` itself when it
    /// already fits or cannot be redrawn — a QR pass over the full frame is slow, not wrong.
    private static func downscaled(_ image: CGImage, to maximumSide: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maximumSide else { return image }

        let scale = maximumSide / longest
        let width = Int((CGFloat(image.width) * scale).rounded())
        let height = Int((CGFloat(image.height) * scale).rounded())

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Vision's read, or `nil` when Vision could not run at all.
    ///
    /// An empty array is not the second opinion it looks like: where Vision has no inference
    /// context it can return successfully having seen nothing, rather than throwing. So empty
    /// is treated the same as `nil` by the caller and falls through to ``detectorPayloads(in:)``.
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

    /// The fallback for when Vision cannot start, or starts and reads nothing: weaker on codes
    /// that are small or at an angle, but it needs no inference context, which is the one thing
    /// Vision cannot get on the simulator. Without it every QR test here would be testing the
    /// failure path.
    ///
    /// Reached on any empty Vision read, including a genuine one over an image holding no QR.
    /// That costs a second pass on the no-QR path, which is free in practice: it runs inside
    /// ``race(_:in:until:)`` against the crop ladder, and the ladder outlasts it by seconds.
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
