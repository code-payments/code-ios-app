import Testing
import UIKit
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("GoldBarMaterialBaker")
struct GoldBarMaterialBakerTests {

    @Test("Rendered Kik code is non-blank")
    func codeRenderer_producesContent() {
        let image = GoldBarCodeRenderer.image(for: .placeholder35, side: 480)
        #expect(image.size.width == 480)
        // Dark dots/arcs over a white backing must pull the average luminance down.
        let composited = compositeOverWhite(image)
        let luminance = averageLuminance(of: composited, in: CGRect(origin: .zero, size: composited.size))
        #expect((luminance ?? 1) < 0.95)
    }

    @Test("Etched code darkens the albedo's code region (etch contrast)")
    func bakedCode_darkensAlbedo() throws {
        let code = GoldBarCodeRenderer.image(for: .placeholder35, side: 480)
        let textures = GoldBarMaterialBaker.bake(.full(code: code, stampLines: ["$25.00"], serial: "5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ"))
        let size = textures.albedo.size

        // Center of the code band vs a plain-gold strip between serial and code.
        let codeRegion = CGRect(x: size.width * 0.35, y: size.height * 0.62, width: size.width * 0.3, height: size.width * 0.2)
        let fieldRegion = CGRect(x: size.width * 0.35, y: size.height * 0.52, width: size.width * 0.3, height: size.width * 0.05)

        let codeLuminance = try #require(averageLuminance(of: textures.albedo, in: codeRegion))
        let fieldLuminance = try #require(averageLuminance(of: textures.albedo, in: fieldRegion))
        #expect(codeLuminance < fieldLuminance * 0.85)
    }

    @Test("All maps are produced at the requested pixel size")
    func bakedTextures_matchRequestedSize() {
        let code = GoldBarCodeRenderer.image(for: .placeholder35, side: 480)
        let config = GoldBarMaterialBaker.Config.full(code: code, stampLines: ["$25.00"], serial: "5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ")
        let textures = GoldBarMaterialBaker.bake(config)
        for image in [textures.albedo, textures.normal, textures.roughness] {
            #expect(image.size.width == config.pixelSize.width)
            #expect(image.size.height == config.pixelSize.height)
        }
    }

    @Test("Preview bake produces all maps at the preview size")
    func previewBake_producesMaps() {
        let code = GoldBarCodeRenderer.image(for: .placeholder35, side: 480)
        let config = GoldBarMaterialBaker.Config.preview(code: code, stampLines: ["$25.00"], serial: "5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ")
        let textures = GoldBarMaterialBaker.bake(config)
        for image in [textures.albedo, textures.normal, textures.roughness] {
            #expect(image.size.width == config.pixelSize.width)
            #expect(image.size.height == config.pixelSize.height)
        }
    }

    // MARK: - Pixel sampling

    private func averageLuminance(of image: UIImage, in rect: CGRect) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let scaleX = CGFloat(cg.width) / image.size.width
        let scaleY = CGFloat(cg.height) / image.size.height
        let pixelRect = CGRect(x: rect.minX * scaleX, y: rect.minY * scaleY,
                               width: rect.width * scaleX, height: rect.height * scaleY).integral
        guard let cropped = cg.cropping(to: pixelRect) else { return nil }

        let w = cropped.width, h = cropped.height
        var gray = [UInt8](repeating: 0, count: w * h)
        let space = CGColorSpaceCreateDeviceGray()
        gray.withUnsafeMutableBufferPointer { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let total = gray.reduce(into: 0.0) { $0 += Double($1) }
        return total / Double(gray.count) / 255
    }

    private func compositeOverWhite(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
    }
}
