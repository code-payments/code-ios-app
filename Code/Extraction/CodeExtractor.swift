//
//  CodeExtractor.swift
//  Code
//
//  Created by Dima Bart on 2021-01-26.
//

import AVKit
import CodeUI
import CodeScanner

class CodeExtractor: CameraSessionExtractor {
    
    private var container = RedundancyContainer<Data>(threshold: 5)
    
    private var isHD: Bool = false
    
    required init() {}
    
    func extract(output: AVCaptureOutput, sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) -> Code.Payload? {
//        let start = CFAbsoluteTimeGetCurrent()
        defer {
            isHD = !isHD
        }
        
        let result: Data? = extractSample(from: sampleBuffer) { sample in
            guard let sample = sample else {
                return nil
            }
            
            guard let data = KikCodes.scan(sample.data, width: sample.width, height: sample.height, hd: isHD) else {
                return nil
            }
            
            return KikCodes.decode(data)
        }

        if let result = result, let payload = try? Code.Payload(data: result) {
            container.insert(result)
            
            if let _ = container.value {
                container.reset()
                return payload
            } else {
                return nil
            }
        }
        
//        print("Process: \(CFAbsoluteTimeGetCurrent() - start) seconds")
        return nil
    }
    
    private func extractSample<T>(from sampleBuffer: CMSampleBuffer, using function: (Sample?) -> T) -> T {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return function(nil)
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        }
        
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return function(nil)
        }
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        let sample = Sample(
            width: width,
            height: height,
            data: Data(bytesNoCopy: base, count: width * height, deallocator: .none)
        )
        
        return function(sample)
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
