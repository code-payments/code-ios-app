//
//  QRModules.swift
//  Flipcash
//

import CoreGraphics
import CoreImage
import Foundation

/// A QR symbol's module matrix, read back from Core Image so the group card can draw the modules
/// itself.
nonisolated struct QRModules: Equatable {

    /// The error correction level a symbol declares in its format information.
    enum ErrorCorrection: Equatable {
        case low, medium, quartile, high
    }

    /// Modules per side, quiet zone excluded.
    let size: Int

    private let bits: [Bool]

    init(size: Int, bits: [Bool]) {
        precondition(bits.count == size * size, "A QR matrix is square")
        self.size = size
        self.bits = bits
    }

    /// Whether the module at column `x`, row `y` is dark. Out of bounds reads as light.
    subscript(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < size, y < size else { return false }
        return bits[y * size + x]
    }

    /// The symbol version, 1 through 40.
    var version: Int { (size - 17) / 4 }

    /// The level the symbol declares, read from its first copy of the format information
    /// (ISO/IEC 18004 §7.9) rather than from what was asked of the encoder.
    var errorCorrection: ErrorCorrection? {
        var format = 0
        func take(_ x: Int, _ y: Int) { format = (format << 1) | (self[x, y] ? 1 : 0) }

        for x in 0...5 { take(x, 8) }
        take(7, 8)
        take(8, 8)
        take(8, 7)
        for y in stride(from: 5, through: 0, by: -1) { take(8, y) }

        switch ((format ^ 0x5412) >> 13) & 0b11 {
        case 0b01: return .low
        case 0b00: return .medium
        case 0b11: return .quartile
        default: return .high
        }
    }

    // MARK: - Encoding -

    private static let context = CIContext(options: [.useSoftwareRenderer: true])

    /// Encodes `text` as a byte-mode symbol at `level`, or nil if Core Image produces nothing.
    ///
    /// Core Image chooses the smallest version that holds the text at that level.
    static func encode(_ text: String, level: String = "Q") -> QRModules? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue(level, forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent)
        else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width == height, width > 0 else { return nil }

        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // Core Image may pad the symbol with a border; the first dark pixel on the diagonal is
        // the corner of the top-left finder pattern.
        guard let offset = (0..<width).first(where: { pixels[$0 * width + $0] < 128 }) else { return nil }
        let size = width - 2 * offset
        guard size >= 21 else { return nil }

        var bits = [Bool](repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                bits[y * size + x] = pixels[(y + offset) * width + (x + offset)] < 128
            }
        }
        return QRModules(size: size, bits: bits)
    }
}
