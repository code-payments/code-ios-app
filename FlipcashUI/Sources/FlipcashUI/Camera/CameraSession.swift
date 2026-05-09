//
//  CameraSession.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
// SAFETY: PassthroughSubject (used for `extraction` and
// `metadataExtraction`) is not yet Sendable upstream. The receive
// path always publishes via `DispatchQueue.main.async`, so subscribers
// observe values on the main queue and cross-isolation reads are sound.
// FOLLOW-UP: Remove when Combine adopts Sendable on PassthroughSubject
// or these are migrated to AsyncSequence.
@preconcurrency import Combine
// SAFETY: AVCaptureSession is documented thread-safe; start()/stop()
// dispatch its mutating calls onto videoDelegate.queue, but
// AVFoundation has not yet adopted Sendable, so capturing the session
// in a @Sendable closure trips compile-time warnings.
// FOLLOW-UP: Remove once AVFoundation annotates AVCaptureSession (and
// the rest of the capture pipeline) as Sendable upstream.
@preconcurrency import AVKit

nonisolated extension AVCaptureDevice {
    /// On a virtual capture device whose first constituent is the ultrawide
    /// lens, `videoZoomFactor = 1.0` engages the ultrawide (what users
    /// perceive as 0.5×). Returns the zoom factor that engages the wide-angle
    /// lens — i.e. the user's "1×". For non-virtual devices and virtual
    /// devices that don't lead with an ultrawide, returns `1.0` unchanged.
    var wideStartZoomFactor: CGFloat {
        guard constituentDevices.first?.deviceType == .builtInUltraWideCamera,
              let wideThreshold = virtualDeviceSwitchOverVideoZoomFactors.first else {
            return 1.0
        }
        return CGFloat(truncating: wideThreshold)
    }
}

public protocol AnyCameraSession {
    var session: AVCaptureSession { get }
}

// The class stays `@MainActor` (via the package default) so SwiftUI lifecycle
// code can call `configureDevices`, `start`, and `stop` directly. The capture
// pipeline runs off-main: AVFoundation invokes the delegate callbacks on the
// queues passed to `setSampleBufferDelegate(_:queue:)` /
// `setMetadataObjectsDelegate(_:queue:)`, not the main queue. The receive path
// therefore has to be `nonisolated` end-to-end — the delegate classes,
// `receiveHandler` closures, extractor protocol, and `extraction` /
// `metadataExtraction` publishers. Letting the default MainActor isolation
// reach those members made every frame cross actor boundaries; under Swift
// 6.2's stricter runtime that trips `dispatch_assert_queue` and crashes the
// camera as soon as it starts.
//
// SAFETY (`@unchecked Sendable`): all stored properties on `CameraSession`
// are immutable after `init`; `isConfigured` is the sole mutable exception
// and is only flipped from inside `configureDevices`, which is `@MainActor`-
// bound. AVCaptureSession is documented thread-safe by Apple and the Combine
// subjects are internally synchronized, so publishing from
// `DispatchQueue.main.async` is sound.
// FOLLOW-UP: Drop `@unchecked` once Combine annotates `PassthroughSubject`
// as `Sendable` and AVFoundation marks `AVCaptureSession` `Sendable`.
public class CameraSession<T>: ObservableObject, AnyCameraSession, @unchecked Sendable where T: CameraSessionExtractor {

    // The publishers, extractor, and session are reachable from the off-main
    // delegate queue via `receiveSampleBuffer`, so they need to be nonisolated.
    // See the class-level SAFETY note for the soundness invariant.
    public nonisolated let extraction = PassthroughSubject<T.Output?, Never>()
    /// Publishes raw string values detected from QR codes via `AVCaptureMetadataOutput`.
    /// Only fires when a new, distinct QR code is detected (duplicate consecutive frames are filtered).
    public nonisolated let metadataExtraction = PassthroughSubject<String, Never>()

    // `T` has no Sendable constraint, hence `nonisolated(unsafe)`.
    public nonisolated(unsafe) let extractor: T
    public nonisolated let session: AVCaptureSession

    private var isConfigured: Bool = false
    private let videoDelegate: VideoDelegate
    private let metadataDelegate: MetadataDelegate
    
    // MARK: - Init -
    
    public init() {
        self.extractor = T.init()
        self.session = AVCaptureSession()
        self.videoDelegate = VideoDelegate()
        self.metadataDelegate = MetadataDelegate()

        self.videoDelegate.receiveHandler = { [weak self] output, sampleBuffer, connection in
            self?.receiveSampleBuffer(output: output, sampleBuffer: sampleBuffer, connection: connection)
        }

        self.metadataDelegate.receiveHandler = { [extraction = metadataExtraction] string in
            DispatchQueue.main.async {
                extraction.send(string)
            }
        }
    }
    
    // MARK: - Configure -
    
    public func configureDevices() throws {
        guard !isConfigured else {
            return
        }
        
        session.beginConfiguration()
        // Ensure commitConfiguration() is always called, even if an
        // early throw leaves the session mid-configuration. Calling
        // stopRunning() on an uncommitted session crashes at runtime.
        defer { session.commitConfiguration() }
        
        // Use 1080 p for a solid balance of resolution and frame‑rate when scanning codes
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }
        
        // Resolve a virtual capture device first so AVFoundation handles
        // ultrawide/wide/telephoto switching automatically as the user pinches
        // across zoom thresholds.
        let preferred: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]

        let device: AVCaptureDevice
        if let resolved = preferred.lazy.compactMap({
            AVCaptureDevice.default($0, for: .video, position: .back)
        }).first {
            device = resolved
        } else {
            throw Error.deviceUnavailable
        }

        // Add input + outputs BEFORE tuning the device. `session.addInput`
        // and the deferred `commitConfiguration` set the device's
        // `activeFormat` to match the session preset, which resets
        // format-dependent properties like `videoZoomFactor`. Tuning
        // afterwards lets the values we write be the last ones standing.

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw Error.inputCreationFailed
        }

        guard session.canAddInput(input) else {
            throw Error.inputAddFailed
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(videoDelegate, queue: videoDelegate.queue)

        guard session.canAddOutput(output) else {
            throw Error.outputAddFailed
        }

        session.addOutput(output)

        let metadataOutput = AVCaptureMetadataOutput()
        metadataOutput.setMetadataObjectsDelegate(metadataDelegate, queue: metadataDelegate.queue)

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            // metadataObjectTypes must be set AFTER adding the output to the session,
            // otherwise the available types list is empty and this will crash.
            if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
                metadataOutput.metadataObjectTypes = [.qr]
            }
        }

        // Tune the camera for close-range, high-speed code scanning.
        try device.lockForConfiguration()

        if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .near
        }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }

        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }

        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }

        // Open at the wide-angle lens on multi-lens devices that lead with an
        // ultrawide so the scanner starts at "1×" instead of the ultrawide
        // constituent's "0.5×".
        device.videoZoomFactor = device.wideStartZoomFactor

        device.unlockForConfiguration()

        isConfigured = true
    }
    
    // MARK: - Start / Stop -
    
    public func start() {
        let session = self.session
        videoDelegate.queue.async {
            session.startRunning()
        }
    }
    
    public func stop() {
        let session = self.session
        videoDelegate.queue.async {
            session.stopRunning()
        }
    }
    
    // MARK: - Sample Buffer -

    /// Invoked from `videoDelegate.queue`. Must stay `nonisolated` so the
    /// extractor work runs off-main; the result is hopped to the main queue
    /// before publishing to subscribers.
    private nonisolated func receiveSampleBuffer(output: AVCaptureOutput, sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) {
        let extracted = extractor.extract(output: output, sampleBuffer: sampleBuffer, connection: connection)
        let extraction = self.extraction
        DispatchQueue.main.async {
            extraction.send(extracted)
        }
    }
}

// MARK: - Error -

extension CameraSession {
    public enum Error: Swift.Error {
        case deviceUnavailable
        case inputCreationFailed
        case inputAddFailed
        case outputAddFailed
    }
}

// MARK: - Video Delegate -

extension CameraSession {
    /// Delegate is `nonisolated` because AVFoundation invokes the
    /// `captureOutput` callbacks on `videoDelegate.queue`, never the main
    /// queue. The default MainActor isolation would force every frame to
    /// hop, which is both wrong (the work is intentionally off-main) and
    /// fatal under Swift 6.2's runtime isolation checks.
    fileprivate nonisolated final class VideoDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

        typealias ReceiveSampleBuffer = (AVCaptureOutput, CMSampleBuffer, AVCaptureConnection) -> Void

        let queue: DispatchQueue

        // SAFETY: receiveHandler is set once during CameraSession.init and
        // only read from videoDelegate.queue (a serial queue) thereafter, so
        // there's no concurrent write contention.
        // FOLLOW-UP: Wrap in a Mutex when adopting Synchronization.
        nonisolated(unsafe) var receiveHandler: ReceiveSampleBuffer?

        // MARK: - Init -

        override init() {
            self.queue = DispatchQueue(label: "com.code.videoDelegate.queue")

            super.init()
        }

        // MARK: - Delegate -

        func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {}

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            receiveHandler?(output, sampleBuffer, connection)
        }
    }
}

// MARK: - Metadata Delegate -

extension CameraSession {
    /// See `VideoDelegate` for the rationale on `nonisolated`.
    fileprivate nonisolated final class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {

        typealias ReceiveString = (String) -> Void

        let queue: DispatchQueue

        // See `VideoDelegate.receiveHandler` for the SAFETY invariant.
        nonisolated(unsafe) var receiveHandler: ReceiveString?

        // SAFETY: lastString is read and written exclusively from
        // metadataDelegate.queue (a serial queue), so writes are sequenced.
        // FOLLOW-UP: Lift to a Mutex with the rest of this class.
        nonisolated(unsafe) private var lastString: String?

        // MARK: - Init -

        override init() {
            self.queue = DispatchQueue(label: "com.code.metadataDelegate.queue")

            super.init()
        }

        // MARK: - Delegate -

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  readable.type == .qr,
                  let string = readable.stringValue else {
                lastString = nil
                return
            }

            guard string != lastString else { return }
            lastString = string

            receiveHandler?(string)
        }
    }
}
