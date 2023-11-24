//
//  CameraSession.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine
import AVKit

public protocol AnyCameraSession {
    var session: AVCaptureSession { get }
}

public class CameraSession<T>: ObservableObject, AnyCameraSession where T: CameraSessionExtractor {
    
    public private(set) var extraction = PassthroughSubject<T.Output?, Never>()

    public let extractor: T
    public let session: AVCaptureSession
    
    private var isConfigured: Bool = false
    private let videoDelegate: VideoDelegate
    
    // MARK: - Init -
    
    public init() {
        self.extractor = T.init()
        self.session = AVCaptureSession()
        self.videoDelegate = VideoDelegate()
        self.videoDelegate.receiveHandler = { [weak self] output, sampleBuffer, connection in
            self?.receiveSampleBuffer(output: output, sampleBuffer: sampleBuffer, connection: connection)
        }
    }
    
    // MARK: - Configure -
    
    public func configureDevices() throws {
        guard !isConfigured else {
            return
        }
        
        session.beginConfiguration()
        
        // Inputs
        
        guard let rearWideDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw Error.deviceUnavailable
        }
        
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
        
        session.commitConfiguration()
        isConfigured = true
    }
    
    // MARK: - Start / Stop -
    
    public func start() {
        videoDelegate.queue.async {
            self.session.startRunning()
        }
    }
    
    public func stop() {
        videoDelegate.queue.async {
            self.session.stopRunning()
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
