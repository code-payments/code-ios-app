import SwiftUI
import FlipcashCore
import FlipcashUI

/// The production gold bar, shown in place of a bill for USDF cash: the amount is
/// stamped where a minted bar carries its weight, the USDF public key is the serial,
/// and the bill's Kik code is etched into the lower band.
struct GoldBarBillView: View {

    let fiat: FiatAmount
    let data: Data
    let canvasSize: CGSize

    @State private var isSceneReady = false

    var body: some View {
        ZStack {
            GoldBarSceneView(
                key: .usdfBill(fiat: fiat, codeData: data),
                lightIntensity: GoldBarScene.defaultLightIntensity,
                environmentIntensity: GoldBarScene.defaultEnvironmentIntensity,
                relief: GoldBarScene.defaultRelief,
                lightAnchor: GoldBarLighting.restAnchor,
                barRotationDegrees: SIMD2(0, 0),
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
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}
