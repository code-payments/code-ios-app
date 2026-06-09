import SceneKit
import UIKit

/// Builds the gold-bar SCNScene and exposes the nodes/material the motion coordinator mutates.
enum GoldBarScene {

    struct Bundle {
        let scene: SCNScene
        let keyLightNode: SCNNode
        let barNode: SCNNode
        let material: SCNMaterial
    }

    /// Full-resolution maps from the most recent bake; a re-presentation skips the
    /// preview phase and opens at full quality immediately.
    static var cachedTextures: (payload: String, textures: GoldBarMaterialBaker.Textures)?

    private static var inflightBake: (payload: String, task: Task<GoldBarMaterialBaker.Textures, Never>)?

    /// Returns the full-resolution maps, baking off the main thread at most once per payload —
    /// concurrent presentations share the in-flight bake instead of spawning their own.
    static func fullTextures(qrPayload: String) async -> GoldBarMaterialBaker.Textures {
        if let cached = cachedTextures, cached.payload == qrPayload {
            return cached.textures
        }
        if let inflight = inflightBake, inflight.payload == qrPayload {
            return await inflight.task.value
        }
        let task = Task.detached(priority: .userInitiated) {
            GoldBarMaterialBaker.bake(.full(qrPayload: qrPayload))
        }
        inflightBake = (qrPayload, task)
        let textures = await task.value
        cachedTextures = (qrPayload, textures)
        inflightBake = nil
        return textures
    }

    static func make(textures: GoldBarMaterialBaker.Textures) -> Bundle {
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.04, alpha: 1)

        // Image-based lighting — on metalness=1 this IS the gold's brightness, so it is bright and broad.
        scene.lightingEnvironment.contents = studioEnvironment()
        scene.lightingEnvironment.intensity = 5.2

        // Portrait minted bar (real 1oz ≈ 24×41×2mm — thin, tall), large face toward the camera (+Z).
        let box = SCNBox(width: 0.60, height: 1.04, length: 0.13, chamferRadius: 0.022)
        // Detailed (markings/QR) only on the front face; plain polished gold on the sides/back.
        // SCNBox material order: front(+Z), right(+X), back(−Z), left(−X), top(+Y), bottom(−Y).
        let detailed = goldMaterial(textures)
        let plain = plainGoldMaterial()
        box.materials = [detailed, plain, plain, plain, plain, plain]

        let barNode = SCNNode(geometry: box)
        scene.rootNode.addChildNode(barNode)

        // Near face-on camera with a slight hero tilt (so the QR scans and a sliver of edge shows).
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.projectionDirection = .vertical
        camera.fieldOfView = 28
        camera.zNear = 0.1
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0.25
        camera.averageGray = 0.18
        camera.whitePoint = 1.7
        camera.bloomIntensity = 0.5
        camera.bloomThreshold = 0.95
        camera.bloomBlurRadius = 10
        cameraNode.camera = camera
        // Face-on by default, pulled back so the whole bar floats with margin; the demo's
        // Rotation slider turns the bar itself to reveal its 3D edges.
        cameraNode.position = SCNVector3(0, 0, 3.35)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        // Moving key — a tall narrow area soft-box whose reflection is a vertical streak that
        // sweeps across the face as the light moves with device tilt.
        let key = SCNLight()
        key.type = .area
        key.areaType = .rectangle
        key.areaExtents = SIMD3<Float>(0.8, 2.4, 0)
        key.intensity = 1100
        key.color = UIColor(red: 1.0, green: 0.90, blue: 0.72, alpha: 1)
        key.castsShadow = false
        let keyLightNode = SCNNode()
        keyLightNode.light = key
        keyLightNode.position = SCNVector3(0, 0.3, 1.4)
        keyLightNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(keyLightNode)

        // Static rim grazing the top/side bevel so the thickness reads as a bright minted edge.
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 320
        rim.color = UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(0.7, 0.5, 0.6)
        rimNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(rimNode)

        return Bundle(scene: scene, keyLightNode: keyLightNode, barNode: barNode, material: detailed)
    }

    private static func goldMaterial(_ textures: GoldBarMaterialBaker.Textures) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.metalness.contents = 1.0
        material.roughness.contents = textures.roughness
        material.diffuse.contents = textures.albedo
        material.normal.contents = textures.normal
        material.normal.intensity = 0.55
        material.clearCoat.contents = 0.8        // thin lacquer → crisp minted sheen on top of the gold
        material.clearCoatRoughness.contents = 0.06
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        return material
    }

    /// Plain polished gold for the bar's sides, top, and back (no markings).
    private static func plainGoldMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.metalness.contents = 1.0
        material.roughness.contents = 0.15
        material.diffuse.contents = UIColor(red: 1.0, green: 0.76, blue: 0.33, alpha: 1)
        material.clearCoat.contents = 0.8
        material.clearCoatRoughness.contents = 0.06
        return material
    }

    /// Bright studio environment: a luminous warm upper hemisphere with broad horizontal soft-boxes,
    /// fading to a navy floor. Broad + bright so a near-mirror metal face reads gold at every held angle.
    private static func studioEnvironment() -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [UIColor(red: 0.82, green: 0.78, blue: 0.70, alpha: 1).cgColor,
                                         UIColor(red: 0.45, green: 0.45, blue: 0.47, alpha: 1).cgColor,
                                         UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1).cgColor] as CFArray,
                                locations: [0, 0.5, 1])!
            cg.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            drawSoftStrip(cg, size: size, centerY: 0.26, height: 0.34, brightness: 1.0)
            drawSoftStrip(cg, size: size, centerY: 0.46, height: 0.08, brightness: 0.7)
            drawSoftStrip(cg, size: size, centerY: 0.54, height: 0.04, brightness: 0.5)
        }
    }

    private static func drawSoftStrip(_ cg: CGContext, size: CGSize, centerY: CGFloat, height: CGFloat, brightness: CGFloat) {
        let stripHeight = size.height * height
        let rect = CGRect(x: 0, y: size.height * centerY - stripHeight / 2, width: size.width, height: stripHeight)
        cg.saveGState()
        cg.clip(to: rect)
        let warm = UIColor(red: 1.0, green: 0.95, blue: 0.84, alpha: brightness)
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [warm.withAlphaComponent(0).cgColor,
                                           warm.cgColor,
                                           warm.withAlphaComponent(0).cgColor] as CFArray,
                                  locations: [0, 0.5, 1])!
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        cg.restoreGState()
    }
}
