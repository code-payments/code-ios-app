//
//  CodeExtractor.swift
//  Code
//
//  Created by Dima Bart on 2021-01-26.
//

import AVKit
import CodeScanner
import FlipcashUI
import FlipcashCore

class CodeExtractor: CameraSessionExtractor {
    
    private var container = RedundancyContainer<Data>(threshold: 1)
    
    required init() {}

    func extract(output: AVCaptureOutput, sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) -> ScannedCode? {
        let sample = extractSample(from: sampleBuffer)
        
        guard let sample = sample else {
            return nil
        }
        
        let payload = Self.processSample(
            sample: sample,
            quality: .best,
            container: &container
        )
        
        return payload
    }
    
    private static func processSample(sample: Sample, quality: KikCodesScanQuality) -> (Data, ScannedCode)? {
        guard let data = KikCodes.scan(sample.data, width: sample.width, height: sample.height, quality: quality) else {
            return nil
        }

        let result = KikCodes.decode(data)

        guard let payload = ScannedCode(data: result) else {
            return nil
        }

        return (result, payload)
    }

    private static func processSample(sample: Sample, quality: KikCodesScanQuality, container: inout RedundancyContainer<Data>) -> ScannedCode? {
        if let (data, payload) = processSample(sample: sample, quality: quality) {
            container.insert(data)
            
            if let _ = container.value {
                container.reset()
                return payload
            } else {
                return nil
            }
        }
        
        return nil
    }
    
    private func extractSample(from sampleBuffer: CMSampleBuffer) -> Sample? {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        }
        
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else {
            return nil
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        let sample = Sample(
            width: width,
            height: height,
            data: Data(bytesNoCopy: base, count: bytesPerRow * height, deallocator: .none)
        )
        
        return sample
    }
}

// MARK: - Sample -

extension CodeExtractor {
    struct Sample {
        let width: Int
        let height: Int
        let data: Data
    }
}
