//
//  CameraSession.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine
@preconcurrency import AVKit

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
        
        guard let rearWideDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw Error.deviceUnavailable
        }
        
        // Tune the camera for close‑range, high‑speed code scanning
        try rearWideDevice.lockForConfiguration()
        
        // Focus configuration
        if rearWideDevice.isAutoFocusRangeRestrictionSupported {
            rearWideDevice.autoFocusRangeRestriction = .near
        }
        if rearWideDevice.isFocusModeSupported(.continuousAutoFocus) {
            rearWideDevice.focusMode = .continuousAutoFocus
        }
        if rearWideDevice.isFocusPointOfInterestSupported {
            rearWideDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        
        // Exposure configuration
        if rearWideDevice.isExposureModeSupported(.continuousAutoExposure) {
            rearWideDevice.exposureMode = .continuousAutoExposure
        }
        if rearWideDevice.isExposurePointOfInterestSupported {
            rearWideDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        
        // White‑balance configuration
        if rearWideDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            rearWideDevice.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        
        // Low‑light boost
        if rearWideDevice.isLowLightBoostSupported {
            rearWideDevice.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
        
        rearWideDevice.unlockForConfiguration()
        
        guard let rearWideInput = try? AVCaptureDeviceInput(device: rearWideDevice) else {
            throw Error.inputCreationFailed
        }
        
        guard session.canAddInput(rearWideInput) else {
            throw Error.inputAddFailed
        }
        
        session.addInput(rearWideInput)
        
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
