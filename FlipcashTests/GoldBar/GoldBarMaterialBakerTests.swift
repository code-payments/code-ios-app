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

    @Test("Small (prewarm-sized) bake produces all maps")
    func smallBake_producesMaps() {
        let code = GoldBarCodeRenderer.image(for: .placeholder35, side: 480)
        let config = GoldBarMaterialBaker.Config(
            pixelSize: CGSize(width: 96, height: 166),
            code: code,
            stampLines: ["$25.00"],
            serial: "TEST",
            scratchCount: 0
        )
        let textures = GoldBarMaterialBaker.bake(config)
        for image in [textures.albedo, textures.normal, textures.roughness] {
            #expect(image.size.width == config.pixelSize.width)
            #expect(image.size.height == config.pixelSize.height)
        }
    }

    // MARK: - Normal map conventions

    @Test("Flat height field maps to the neutral normal")
    func normalMap_flatField_neutral() {
        let flat = grayImage(width: 16, height: 16) { _, _ in 0.5 }
        let normal = GoldBarMaterialBaker.normalMap(from: flat)
        let px = rgba(of: normal, x: 8, y: 8)
        #expect(abs(Int(px.r) - 128) <= 1)
        #expect(abs(Int(px.g) - 128) <= 1)
        #expect(px.b >= 254)
    }

    @Test("Height rising to the right tilts normals away from +X (red below neutral)")
    func normalMap_horizontalRamp_redBelowNeutral() {
        let ramp = grayImage(width: 16, height: 16) { x, _ in CGFloat(x) / 15 }
        let normal = GoldBarMaterialBaker.normalMap(from: ramp)
        let px = rgba(of: normal, x: 8, y: 8)
        #expect(px.r < 120)
        #expect(abs(Int(px.g) - 128) <= 1)
    }

    @Test("Height rising downward keeps green above neutral (pressed-look convention)")
    func normalMap_verticalRamp_greenAboveNeutral() {
        let ramp = grayImage(width: 16, height: 16) { _, y in CGFloat(y) / 15 }
        let normal = GoldBarMaterialBaker.normalMap(from: ramp)
        let px = rgba(of: normal, x: 8, y: 8)
        #expect(px.g > 136)
        #expect(abs(Int(px.r) - 128) <= 1)
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

    private func grayImage(width: Int, height: Int, value: (Int, Int) -> CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            for y in 0..<height {
                for x in 0..<width {
                    UIColor(white: value(x, y), alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    private func rgba(of image: UIImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let cg = image.cgImage!
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBufferPointer { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        }
        return (pixel[0], pixel[1], pixel[2])
    }
}
