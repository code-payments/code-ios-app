import SceneKit
import UIKit

/// Builds the gold-bar SCNScene and exposes the nodes/material the motion coordinator mutates.
enum GoldBarScene {

    struct Bundle {
        let scene: SCNScene
        let keyLightNode: SCNNode
        let material: SCNMaterial
    }

    static func make(qrPayload: String) -> Bundle {
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.04, alpha: 1)

        // Image-based lighting — this is what makes metal look real.
        scene.lightingEnvironment.contents = studioEnvironment()
        scene.lightingEnvironment.intensity = 2.2

        // Geometry: a chamfered bar, large face toward the camera (−Z).
        let box = SCNBox(width: 1.0, height: 0.58, length: 0.26, chamferRadius: 0.016)
        let textures = GoldBarMaterialBaker.bake(.init(
            pixelSize: CGSize(width: 1024, height: 594),  // matches the 1.0:0.58 face aspect
            qrPayload: qrPayload,
            stampLines: ["FINE GOLD", "999.9", "1 oz"]
        ))
        // Detailed (QR/text) only on the front face; plain polished gold on the sides/back.
        // SCNBox material order: front(+Z), right(+X), back(−Z), left(−X), top(+Y), bottom(−Y).
        let detailed = goldMaterial(textures)
        let plain = plainGoldMaterial()
        box.materials = [detailed, plain, plain, plain, plain, plain]

        let barNode = SCNNode(geometry: box)
        scene.rootNode.addChildNode(barNode)

        // Fixed camera, straight on, with subtle bloom on the hot specular.
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        // Fit the field of view to the vertical axis; the host view is constrained to the
        // bar's aspect ratio, so the whole bar lands inside the frame with margin.
        camera.projectionDirection = .vertical
        camera.fieldOfView = 32
        camera.zNear = 0.1
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.35
        camera.bloomThreshold = 0.75
        camera.bloomBlurRadius = 8
        cameraNode.camera = camera
        // Slight 3/4 angle reveals the bar's depth (top + side), so it reads as a solid ingot.
        cameraNode.position = SCNVector3(0.30, 0.46, 1.79)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        // Directional key light — the moving hot highlight.
        let light = SCNLight()
        light.type = .directional
        light.intensity = 300
        light.color = UIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 1)
        let keyLightNode = SCNNode()
        keyLightNode.light = light
        keyLightNode.position = SCNVector3(0, 0.3, 1)
        keyLightNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(keyLightNode)

        return Bundle(scene: scene, keyLightNode: keyLightNode, material: detailed)
    }

    private static func goldMaterial(_ textures: GoldBarMaterialBaker.Textures) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.metalness.contents = 1.0
        material.roughness.contents = textures.roughness
        material.diffuse.contents = textures.albedo
        material.normal.contents = textures.normal
        material.normal.intensity = 0.85
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        return material
    }

    /// Plain polished gold for the bar's sides, top, and back (no markings).
    private static func plainGoldMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.metalness.contents = 1.0
        material.roughness.contents = 0.3
        material.diffuse.contents = UIColor(red: 0.95, green: 0.74, blue: 0.36, alpha: 1)
        return material
    }

    /// Studio environment: a graded sky plus horizontal strip soft-boxes. The strips reflect
    /// as elongated streaks across the metal (not round blobs), which reads as real bullion.
    private static func studioEnvironment() -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Graded sky: brighter top (overhead light), dark floor.
            let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [UIColor(white: 0.34, alpha: 1).cgColor,
                                         UIColor(white: 0.17, alpha: 1).cgColor,
                                         UIColor(white: 0.05, alpha: 1).cgColor] as CFArray,
                                locations: [0, 0.55, 1])!
            cg.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // Horizontal strip soft-boxes → horizontal streak reflections.
            drawSoftStrip(cg, size: size, centerY: 0.20, height: 0.11, brightness: 1.0)
            drawSoftStrip(cg, size: size, centerY: 0.38, height: 0.05, brightness: 0.65)
            drawSoftStrip(cg, size: size, centerY: 0.50, height: 0.035, brightness: 0.45)
        }
    }

    private static func drawSoftStrip(_ cg: CGContext, size: CGSize, centerY: CGFloat, height: CGFloat, brightness: CGFloat) {
        let stripHeight = size.height * height
        let rect = CGRect(x: 0, y: size.height * centerY - stripHeight / 2, width: size.width, height: stripHeight)
        cg.saveGState()
        cg.clip(to: rect)
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(white: 1, alpha: 0).cgColor,
                                           UIColor(white: 1, alpha: brightness).cgColor,
                                           UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                                  locations: [0, 0.5, 1])!
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        cg.restoreGState()
    }
}
