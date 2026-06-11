import SceneKit
import UIKit
import FlipcashUI

/// Compiles the gold bar's SceneKit shaders once, offscreen, so the first real bar
/// presents without the multi-second cold-compile stall — the gold bar's equivalent
/// of ScanScreen keeping a BillView pre-rendered in the bill canvas.
@MainActor
final class GoldBarPrewarmer {

    static let shared = GoldBarPrewarmer()

    private var warmedView: SCNView?
    private var started = false

    /// Idempotent; call when the scan screen settles. The texture content doesn't
    /// matter — shader variants are content-independent, so a placeholder scene
    /// compiles everything a real bill's bar will need.
    func prewarmIfNeeded() {
        guard !started else { return }
        started = true
        Task {
            try? await Task.sleep(for: .seconds(1))  // let the scan screen settle first
            let code = GoldBarCodeRenderer.image(for: .placeholder35, side: 64)
            let textures = GoldBarMaterialBaker.bake(GoldBarMaterialBaker.Config(
                pixelSize: CGSize(width: 96, height: 166),
                code: code,
                stampLines: ["0"],
                serial: "0",
                scratchCount: 0
            ))
            let bundle = GoldBarScene.make(textures: textures)
            let view = SCNView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            await withCheckedContinuation { continuation in
                view.prepare([bundle.scene]) { _ in continuation.resume() }
            }
            view.scene = bundle.scene
            warmedView = view  // retained so the compiled pipeline stays warm
        }
    }
}
