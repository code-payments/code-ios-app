import SwiftUI

/// The gold bar with its loading cover: a flat stand-in shows instantly and
/// fades out once the SceneKit scene is attached and renderable.
struct GoldBarView: View {

    let key: GoldBarTextureStore.Key
    var tuning: GoldBarTuning = .standard

    @State private var isSceneReady = false

    var body: some View {
        ZStack {
            GoldBarSceneView(
                key: key,
                tuning: tuning,
                onSceneReady: {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isSceneReady = true
                    }
                }
            )

            GoldBarPlaceholder()
                .opacity(isSceneReady ? 0 : 1)
                .allowsHitTesting(false)
        }
    }
}

/// Flat gold stand-in shown while the scene attaches. Its silhouette is derived
/// from the scene's bar geometry so the crossfade doesn't jump.
struct GoldBarPlaceholder: View {
    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height * GoldBarScene.viewportHeightFill
            let width = height * (GoldBarScene.barSize.x / GoldBarScene.barSize.y)
            RoundedRectangle(cornerRadius: height * (GoldBarScene.chamferRadius / GoldBarScene.barSize.y))
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.85, blue: 0.45),
                            Color(red: 0.93, green: 0.72, blue: 0.32),
                            Color(red: 0.80, green: 0.58, blue: 0.22),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.4).opacity(0.35), radius: 24)
        }
    }
}
