//
//  CodeExtractor.swift
//  Code
//
//  Created by Dima Bart on 2021-01-26.
//

import AVKit
import CodeUI
import CodeServices
import CodeScanner
import Accelerate

class CodeExtractor: CameraSessionExtractor {
    
    private var container = RedundancyContainer<Data>(threshold: 5)
    
    private var isHD: Bool = false
    
    required init() {}
    
    static func extract(from image: UIImage) -> Code.Payload? {
        if let wholeImage = image.extractSample() {
            var container = RedundancyContainer<Data>(threshold: 1)
            if let payload = Self.processSample(
                sample: wholeImage,
                hd: true,
                container: &container
            ) {
                print("Success on whole scan")
                return payload
            }
        }
        
        return image.slidingWindowSearch { sample in
            var container = RedundancyContainer<Data>(threshold: 1)
            return Self.processSample(
                sample: sample,
                hd: true,
                container: &container
            )
        }
    }
    
    func extract(output: AVCaptureOutput, sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) -> Code.Payload? {
        defer {
            isHD = !isHD
        }
        
        let sample = extractSample(from: sampleBuffer)
        
        guard let sample = sample else {
            return nil
        }
        
        let payload = Self.processSample(
            sample: sample,
            hd: isHD,
            container: &container
        )
        
        return payload
    }
    
    private static func processSample(sample: Sample, hd: Bool, container: inout RedundancyContainer<Data>) -> Code.Payload? {
        guard let data = KikCodes.scan(sample.data, width: sample.width, height: sample.height, hd: hd) else {
            return nil
        }
        
        let result = KikCodes.decode(data)

        if let payload = try? Code.Payload(data: result) {
            container.insert(result)
            
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

// MARK: - UIImage -

extension UIImage {

    // Perform sliding window search on a 3x3 grid with 50% overlap in top-to-bottom, left-to-right order
    func slidingWindowSearch<T>(
        scan: (CodeExtractor.Sample) -> T? // Scan function for each window
    ) -> T? {
        // Get image dimensions
        let width  = Int(self.size.width)
        let height = Int(self.size.height)
        
        // Calculate window size for a 3x3 grid
        let windowWidth  = width  / 3
        let windowHeight = height / 3
        
        // Define overlap as 50% of the window size
        let stepX = windowWidth  / 2
        let stepY = windowHeight / 2
        
        var windows: [CGRect] = []
        
        // Iterate through grid top to bottom, left to right
        let rowCount = height / stepY
        for r in 0..<rowCount {
            
            let columnCount = width / stepX
            for c in 0..<columnCount {
                let x = c * stepX
                let y = r * stepY

                let windowRect = CGRect(
                    x: x,
                    y: y,
                    width: windowWidth,
                    height: windowHeight
                )
                
                windows.append(windowRect)
            }
        }
        
        let payload: T? = windows.iterateCenterOut { index, windowRect in
            // Crop the image for the current window
            guard let windowImage = self.cropped(to: windowRect) else {
                return nil
            }
            
            print("Scanning \(index): \(windowRect)")
            
            // Extract YUV sample for the window
            guard let windowSample = windowImage.extractSample() else {
                return nil
            }

            // Perform scan on the extracted sample
            if let result = scan(windowSample) {
                return result // Return result if found
            }
            
            return nil
        }
        
        return payload
    }
    
    // Helper function to crop a UIImage to a specific CGRect
    private func cropped(to rect: CGRect) -> UIImage? {
        guard let cgImage = self.cgImage?.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    func extractSample() throws -> CodeExtractor.Sample? {
        guard let cgImage = cgImage else { return nil }

        let start = Date.now.timeIntervalSince1970
        
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
            throw Error.failedToGenerateConversionInfo
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
            throw Error.failedToConvert
        }

        // 6. Split the interleaved UV plane into separate U and V planes
        
        var uPlane = Data(count: (width / 2) * (height / 2))
        var vPlane = Data(count: (width / 2) * (height / 2))
        
        uvPlane.withUnsafeBytes { pointer in
            let uvBytes = pointer.bindMemory(to: UInt8.self)
            
            uPlane.withUnsafeMutableBytes { uPointer in
                vPlane.withUnsafeMutableBytes { vPointer in
                    
                    let u = uPointer.bindMemory(to: UInt8.self).baseAddress!
                    let v = vPointer.bindMemory(to: UInt8.self).baseAddress!
            
                    for i in 0..<(width / 2 * height / 2) {
                        u[i] = uvBytes[2 * i]
                        v[i] = uvBytes[2 * i + 1]
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
        
        print("Conversion took: \(Date.now.timeIntervalSince1970 - start) seconds")

        return .init(
            width: width,
            height: height,
            data: combinedData
        )
    }
    
    enum Error: Swift.Error {
        case failedToGenerateConversionInfo
        case failedToConvert
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

extension Array {
    func iterateCenterOut<T>(action: (Int, Element) -> T?) -> T? {
        let centerIndex = self.count / 2
        
        // Iterate over the array, expanding from the center outwards
        for offset in 0..<self.count {
            let index: Int
            if offset == 0 {
                index = centerIndex // Start with the center
            } else if offset % 2 == 1 {
                index = centerIndex + (offset + 1) / 2 // Right of the center
            } else {
                index = centerIndex - offset / 2 // Left of the center
            }
            
            // Ensure the index is within bounds
            if index >= 0 && index < self.count {
                if let result = action(index, self[index]) {
                    return result
                }
            }
        }
        
        return nil
    }
}
