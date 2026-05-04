//
//  CameraSession.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine
import FlipcashCore
@preconcurrency import AVKit

private let logger = Logger(label: "flipcash.camera")

extension AVCaptureDevice {
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

@MainActor
public protocol AnyCameraSession {
    var session: AVCaptureSession { get }
}

@MainActor
public class CameraSession<T>: ObservableObject, AnyCameraSession where T: CameraSessionExtractor {
    
    public private(set) var extraction = PassthroughSubject<T.Output?, Never>()
    /// Publishes raw string values detected from QR codes via `AVCaptureMetadataOutput`.
    /// Only fires when a new, distinct QR code is detected (duplicate consecutive frames are filtered).
    public private(set) var metadataExtraction = PassthroughSubject<String, Never>()

    public let extractor: T
    public let session: AVCaptureSession

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

        self.metadataDelegate.receiveHandler = { [weak self] string in
            DispatchQueue.main.async {
                self?.metadataExtraction.send(string)
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
        
        // Inputs

        // Virtual devices first — AVFoundation handles ultrawide/wide/telephoto
        // switching automatically as the user pinches across zoom thresholds.
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

        // Tune the camera for close‑range, high‑speed code scanning
        try device.lockForConfiguration()

        // Focus configuration
        if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .near
        }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }

        // Exposure configuration
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }

        // White‑balance configuration
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }

        // Low‑light boost
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }

        // Default to the wide-angle lens on multi-lens devices that lead with
        // an ultrawide. Without this, iPhone Pro / Plus models open at 0.5×.
        device.videoZoomFactor = device.wideStartZoomFactor

        device.unlockForConfiguration()

        logger.info("Configured capture device", metadata: [
            "deviceType": "\(device.deviceType.rawValue)",
            "constituents": "\(device.constituentDevices.map(\.deviceType.rawValue).joined(separator: ","))",
            "switchovers": "\(device.virtualDeviceSwitchOverVideoZoomFactors)",
            "startZoom": "\(device.videoZoomFactor)",
            "minZoom": "\(device.minAvailableVideoZoomFactor)",
            "maxZoom": "\(device.maxAvailableVideoZoomFactor)",
        ])

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw Error.inputCreationFailed
        }

        guard session.canAddInput(input) else {
            throw Error.inputAddFailed
        }

        session.addInput(input)
        
        // Outputs
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(videoDelegate, queue: videoDelegate.queue)
        
        guard session.canAddOutput(output) else {
            throw Error.outputAddFailed
        }
        
        session.addOutput(output)

        // QR Code Output

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
    
    private func receiveSampleBuffer(output: AVCaptureOutput, sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) {
        if let output = extractor.extract(output: output, sampleBuffer: sampleBuffer, connection: connection) {
            DispatchQueue.main.async {
                self.extraction.send(output)
            }
        } else {
            DispatchQueue.main.async {
                self.extraction.send(nil)
            }
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
    private class VideoDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        
        typealias ReceiveSampleBuffer = (AVCaptureOutput, CMSampleBuffer, AVCaptureConnection) -> Void
        
        let queue: DispatchQueue
        
        var receiveHandler: ReceiveSampleBuffer?

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
    private class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {

        typealias ReceiveString = (String) -> Void

        let queue: DispatchQueue

        var receiveHandler: ReceiveString?

        private var lastString: String?

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
