import SwiftUI
import SceneKit

/// Hosts the pooled gold-bar SCNView for one presentation: adopts it from
/// `GoldBarSceneHost`, parents it, and releases it on dismantle.
struct GoldBarSceneView: UIViewRepresentable {

    let key: GoldBarTextureStore.Key
    var tuning: GoldBarTuning = .standard
    /// Called once the scene is attached and renderable — the placeholder above can fade out.
    var onSceneReady: () -> Void

    /// Motion-driven rendering stays out of the cover transition: re-rendering
    /// the scene on the main thread while the presentation animates drops frames.
    private static let motionStartDelay: Duration = .milliseconds(600)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        let coordinator = context.coordinator
        let onReady = onSceneReady
        Task {
            // Liveness BEFORE adopting: a presenter dismantled before this task
            // runs must not steal ownership (and content) from a live one.
            guard !coordinator.isStopped else { return }
            guard let view = await GoldBarSceneHost.shared.adopt(key: key, tuning: tuning, token: coordinator.token),
                  !coordinator.isStopped else { return }
            view.frame = container.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(view)
            onReady()

            try? await Task.sleep(for: Self.motionStartDelay)
            guard !coordinator.isStopped else { return }
            GoldBarSceneHost.shared.startMotion(token: coordinator.token)
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        GoldBarSceneHost.shared.apply(tuning, token: context.coordinator.token)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.isStopped = true
        GoldBarSceneHost.shared.release(token: coordinator.token)
    }

    @MainActor
    final class Coordinator {
        var isStopped = false
        var token: ObjectIdentifier { ObjectIdentifier(self) }
    }
}
