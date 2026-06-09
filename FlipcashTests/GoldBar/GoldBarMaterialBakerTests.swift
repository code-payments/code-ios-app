import Testing
import CoreImage
import UIKit
@testable import Flipcash

@Suite("GoldBarMaterialBaker")
struct GoldBarMaterialBakerTests {

    private static let config = GoldBarMaterialBaker.Config.full(
        qrPayload: "https://flipcash.com/gold-bar-demo"
    )

    @Test("Baked etched QR still decodes to its payload (scannable)")
    func bakedQR_decodesToPayload() throws {
        let textures = GoldBarMaterialBaker.bake(Self.config)
        let ciImage = CIImage(image: textures.albedo)!
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )!
        let features = detector.features(in: ciImage).compactMap { $0 as? CIQRCodeFeature }
        #expect(features.contains { $0.messageString == Self.config.qrPayload })
    }

    @Test("All maps are produced at the requested pixel size")
    func bakedTextures_matchRequestedSize() {
        let textures = GoldBarMaterialBaker.bake(Self.config)
        let expected = Self.config.pixelSize
        for image in [textures.albedo, textures.normal, textures.roughness] {
            #expect(image.size.width == expected.width)
            #expect(image.size.height == expected.height)
        }
    }

    @Test("Preview bake produces all maps at the preview size")
    func previewBake_producesMaps() {
        let config = GoldBarMaterialBaker.Config.preview(qrPayload: "https://flipcash.com/gold-bar-demo")
        let textures = GoldBarMaterialBaker.bake(config)
        for image in [textures.albedo, textures.normal, textures.roughness] {
            #expect(image.size.width == config.pixelSize.width)
            #expect(image.size.height == config.pixelSize.height)
        }
    }
}
