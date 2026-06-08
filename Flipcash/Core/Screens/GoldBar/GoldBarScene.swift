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
        scene.lightingEnvironment.intensity = 1.6

        // Geometry: a chamfered bar, large face toward the camera (−Z).
        let box = SCNBox(width: 1.0, height: 0.58, length: 0.14, chamferRadius: 0.022)
        let textures = GoldBarMaterialBaker.bake(.init(
            pixelSize: CGSize(width: 1024, height: 594),  // matches the 1.0:0.58 face aspect
            qrPayload: qrPayload,
            stampLines: ["FINE GOLD", "999.9", "1 oz"]
        ))
        let material = goldMaterial(textures)
        box.materials = [material]

        let barNode = SCNNode(geometry: box)
        scene.rootNode.addChildNode(barNode)

        // Fixed camera, straight on, with subtle bloom on the hot specular.
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.35
        camera.bloomThreshold = 0.75
        camera.bloomBlurRadius = 8
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 2.2)
        scene.rootNode.addChildNode(cameraNode)

        // Directional key light — the moving hot highlight.
        let light = SCNLight()
        light.type = .directional
        light.intensity = 900
        light.color = UIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 1)
        let keyLightNode = SCNNode()
        keyLightNode.light = light
        keyLightNode.position = SCNVector3(0, 0.3, 1)
        keyLightNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(keyLightNode)

        return Bundle(scene: scene, keyLightNode: keyLightNode, material: material)
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

    /// Warm studio-gradient environment with a few bright soft-boxes for rich reflections.
    private static func studioEnvironment() -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor(red: 0.22, green: 0.20, blue: 0.17, alpha: 1).cgColor,
                UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1).cgColor
            ]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // Soft-box highlights.
            for spot in [CGPoint(x: 0.28, y: 0.32), CGPoint(x: 0.7, y: 0.22), CGPoint(x: 0.5, y: 0.6)] {
                let center = CGPoint(x: spot.x * size.width, y: spot.y * size.height)
                let radius = size.width * 0.16
                let radial = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [UIColor(white: 1, alpha: 1).cgColor,
                                                 UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                                        locations: [0, 1])!
                cg.drawRadialGradient(radial, startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: radius, options: [])
            }
        }
    }
}
