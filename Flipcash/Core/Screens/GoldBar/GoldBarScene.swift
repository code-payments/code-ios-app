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

    /// Unit direction the key light sits in, for a rest anchor (x lateral, y elevation).
    static func lightDirection(anchor: SIMD2<Double>) -> SIMD3<Double> {
        simd_normalize(SIMD3(anchor.x, anchor.y, 1))
    }

    static func make(textures: GoldBarMaterialBaker.Textures) -> Bundle {
        let scene = SCNScene()
        // Transparent: the bar composites over whatever is behind it (the scan screen,
        // the demo's backdrop) exactly like the bill does.
        scene.background.contents = UIColor.clear

        // Image-based lighting — on metalness=1 this IS the gold's brightness, so it is bright and broad.
        scene.lightingEnvironment.contents = environmentImage
        scene.lightingEnvironment.intensity = CGFloat(GoldBarTuning.standard.environmentIntensity)

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
        // Face-on, framed so the bar fills ~80% of the viewport height — bill-sized
        // when hosted in the bill canvas, with margin for the slight motion lean.
        cameraNode.position = SCNVector3(0, 0, 2.6)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        // Fixed key — a tall narrow area soft-box anchored at the tuned rest position;
        // device tilt leans the bar itself, sweeping its reflection of this light.
        let key = SCNLight()
        key.type = .area
        key.areaType = .rectangle
        key.areaExtents = SIMD3<Float>(0.8, 2.4, 0)
        key.intensity = CGFloat(GoldBarTuning.standard.lightIntensity)
        key.color = UIColor(red: 1.0, green: 0.90, blue: 0.72, alpha: 1)
        key.castsShadow = false
        let keyLightNode = SCNNode()
        keyLightNode.light = key
        let anchor = lightDirection(anchor: GoldBarTuning.standard.lightAnchor)
        keyLightNode.position = SCNVector3(Float(anchor.x), Float(anchor.y), Float(anchor.z))
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
        material.normal.intensity = CGFloat(GoldBarTuning.standard.relief)
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

    /// Rendered once — identical for every scene (bill, demo, prewarm).
    private static let environmentImage = studioEnvironment()

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
