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

@preconcurrency import Accelerate

class CodeExtractor: CameraSessionExtractor {
    
    private var container = RedundancyContainer<Data>(threshold: 5)
    
    private var isHD: Bool = false
    
    required init() {}
    
    static func extract(from image: UIImage) throws -> CashCode.Payload? {
        let qualities: [KikCodesScanQuality] = [
            .low,
            .medium,
            .high,
            .best,
        ]
        
        if let wholeImage = try image.extractSample() {
            for quality in qualities {
                if let (_, payload) = Self.processSample(sample: wholeImage, quality: quality) {
                    print("Whole scan [X]: \(quality)")
                    return payload
                } else {
                    print("Whole scan [ ]: \(quality)")
                }
            }
        }
        
        return try image.slidingWindowSearch { sample in
            Self.processSample(sample: sample, quality: .high)?.1
        }
    }
    
    func extract(output: AVCaptureOutput, sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) -> CashCode.Payload? {
        defer {
            isHD = !isHD
        }
        
        let sample = extractSample(from: sampleBuffer)
        
        guard let sample = sample else {
            return nil
        }
        
        let payload = Self.processSample(
            sample: sample,
            quality: isHD ? .best : .high,
            container: &container
        )
        
        return payload
    }
    
    private static func processSample(sample: Sample, quality: KikCodesScanQuality) -> (Data, CashCode.Payload)? {
        guard let data = KikCodes.scan(sample.data, width: sample.width, height: sample.height, quality: quality) else {
            return nil
        }
        
        let result = KikCodes.decode(data)

        guard let payload = try? CashCode.Payload(data: result) else {
            return nil
        }
        
        return (result, payload)
    }
    
    private static func processSample(sample: Sample, quality: KikCodesScanQuality, container: inout RedundancyContainer<Data>) -> CashCode.Payload? {
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
        
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        let sample = Sample(
            width: width,
            height: height,
            data: Data(bytesNoCopy: base, count: width * height, deallocator: .none)
        )
        
        return sample
    }
}

extension CodeExtractor {
    enum Error: Swift.Error {
        case failedToGenerateConversionInfo
        case failedToConvert
    }
}

// MARK: - UIImage -

extension UIImage {

    /// Perform sliding window search on a 3x3 grid with 50% overlap in top-to-bottom, left-to-right order
    func slidingWindowSearch<T>(scan: (CodeExtractor.Sample) -> T?) throws -> T? {
        
        // This is necessary because sometimes portrait images,
        // for some reason, report landscape size and the orientation
        // doesn't match the dimensions so we have to invert manually
        let invert: Bool
        switch imageOrientation {
        case .up, .upMirrored, .down, .downMirrored:
            invert = false
        case .left, .right, .leftMirrored, .rightMirrored:
            invert = true
        @unknown default:
            invert = false
        }
        
        let width  = Int(invert ? size.height : size.width)
        let height = Int(invert ? size.width  : size.height)
        
        let minSize = 20
        
        guard width >= minSize && height >= minSize else {
            // Image resolution won't provide
            // sufficiently scannable code
            return nil
        }
        
        // Calculate window size for a 3x3 grid
        let windowWidth  = width  / 3
        let windowHeight = height / 3
        
        // Define overlap as 50% of the window size
        let stepX = windowWidth  / 2
        let stepY = windowHeight / 2
        
        // Precompute all the windows first
        var windows: [CGRect] = []
        
        let rCount = 5
        let cCount = 5
        
        for r in 0..<rCount {
            for c in 0..<cCount {
                
                let x = c * stepX
                let y = r * stepY
                
                windows.append(
                    CGRect(
                        x: x,
                        y: y,
                        width: windowWidth,
                        height: windowHeight
                    )
                )
            }
        }
        
//        print("Window (\(windows.count)): \(windows[0].size)")
//        print("\(windows.map { "\($0.origin.x), \($0.origin.y)" })")        
        
        // For each window, feed it into the code scanner and see
        // if we get any scanned payload, exit as soon as we find one
        let payload: T? = try windows.iterateCenterOut { index, windowRect in
            // Crop the image for the current window
            guard let windowImage = self.cropped(to: windowRect) else {
                return nil
            }
            
//            print("Scanning \(index): \(windowRect.origin)")
            
            // Extract YUV sample for the window
            guard let windowSample = try windowImage.extractSample() else {
                return nil
            }

            // Perform scan on the extracted sample
            if let result = scan(windowSample) {
                return result
            }
            
            return nil
        }
        
        return payload
    }
    
    private func cropped(to rect: CGRect) -> UIImage? {
        guard let cgImage = cgImage?.cropping(to: rect) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    func extractSample() throws -> CodeExtractor.Sample? {
        guard let cgImage = cgImage else { return nil }
        
        let width  = cgImage.width
        let height = cgImage.height

        // 1. Draw the RGB image and get the raw bitmap
        
        var rgbaData = Data(count: width * height * 4)

        guard let context = CGContext(
            data: rgbaData.withUnsafeMutableBytes { $0.baseAddress },
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 2. Set up the vImage buffer for the source (RGBA)
        
        var sourceBuffer = rgbaData.withUnsafeMutableBytes { pointer -> vImage_Buffer in
            vImage_Buffer(
                data: pointer.baseAddress!,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: width * 4
            )
        }

        // 3. Allocate memory for the Y and UV plane buffers
        
        var yPlane  = Data(count: width * height)
        var uvPlane = Data(count: width * height / 2) // Interleaved UV plane (4:2:0)
        
        var yBuffer = yPlane.withUnsafeMutableBytes { pointer -> vImage_Buffer in
            vImage_Buffer(
                data: pointer.baseAddress!,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: width
            )
        }
        
        var uvBuffer = uvPlane.withUnsafeMutableBytes { pointer -> vImage_Buffer in
            vImage_Buffer(
                data: pointer.baseAddress!,
                height: vImagePixelCount(height / 2),
                width: vImagePixelCount(width / 2),
                rowBytes: width
            )
        }

        // 4. Generate the conversion info for the operation
        
        var pixelRange = vImage_YpCbCrPixelRange(
            Yp_bias: 0,
            CbCr_bias: 128,
            YpRangeMax: 255,
            CbCrRangeMax: 255,
            YpMax: 255,
            YpMin: 0,
            CbCrMax: 255,
            CbCrMin: 0
        )
        
        var info = vImage_ARGBToYpCbCr()
        let generateInfoResult = vImageConvert_ARGBToYpCbCr_GenerateConversion(
            kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2, // Use the BT.709 matrix
            &pixelRange,
            &info,
            kvImageARGB8888,
            kvImage420Yp8_CbCr8,
            vImage_Flags(kvImageNoFlags)
        )
        
        guard generateInfoResult == kvImageNoError else {
            trace(.failure, components: "Failed to generate YUV conversion info: \(generateInfoResult)")
            throw CodeExtractor.Error.failedToGenerateConversionInfo
        }
        
        // 5. Perform the RGB to YUV 420 conversion info using the
        // ITU-R BT.709 conversion matrix and the pixel range
        
        let conversionResult = vImageConvert_ARGB8888To420Yp8_CbCr8(
            &sourceBuffer,
            &yBuffer,
            &uvBuffer,
            &info,
            nil,
            vImage_Flags(kvImageNoFlags)
        )

        guard conversionResult == kvImageNoError else {
            trace(.failure, components: "Failed to convert image to YUV: \(conversionResult)")
            throw CodeExtractor.Error.failedToConvert
        }

        // 6. Split the interleaved UV plane into separate U and V planes
        
        var uPlane = Data(count: (width / 2) * (height / 2))
        var vPlane = Data(count: (width / 2) * (height / 2))
        
        uvPlane.withUnsafeBytes { uvBytes in
            uPlane.withUnsafeMutableBytes { uPointer in
                vPlane.withUnsafeMutableBytes { vPointer in
                    
                    let uv = uvBytes.bindMemory(to: UInt8.self).baseAddress!
                    let u = uPointer.bindMemory(to: UInt8.self).baseAddress!
                    let v = vPointer.bindMemory(to: UInt8.self).baseAddress!
                    
                    let count = width / 2 * height / 2

                    // Process the UV plane by unrolling the loop for better performance
                    var i = 0
                    while i < count {
                        // Copy two UV pairs per iteration (unrolled loop)
                        u[i] = uv[2 * i]     // U plane from even index
                        v[i] = uv[2 * i + 1] // V plane from odd index
                        
                        if i + 1 < count {
                            u[i + 1] = uv[2 * (i + 1)]
                            v[i + 1] = uv[2 * (i + 1) + 1]
                        }
                        
                        i += 2 // Increment by 2 due to unrolling
                    }
                }
            }
        }

        // 7. Combine Y, U, and V planes
        var combinedData = Data()
        combinedData.reserveCapacity(yPlane.count + uPlane.count + vPlane.count)
        
        combinedData.append(yPlane)
        combinedData.append(uPlane)
        combinedData.append(vPlane)

        return .init(
            width: width,
            height: height,
            data: combinedData
        )
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

private extension Array {
    func iterateCenterOut<T>(action: (Int, Element) throws -> T?) rethrows -> T? {
        let centerIndex = count / 2
        for offset in 0..<count {
            let index: Int
            if offset == 0 {
                index = centerIndex // Start with the center
            } else if offset % 2 == 1 {
                index = centerIndex + (offset + 1) / 2 // Right of the center
            } else {
                index = centerIndex - offset / 2 // Left of the center
            }
            
            if index >= 0 && index < count {
                if let result = try action(index, self[index]) {
                    return result
                }
            }
        }
        
        return nil
    }
}
