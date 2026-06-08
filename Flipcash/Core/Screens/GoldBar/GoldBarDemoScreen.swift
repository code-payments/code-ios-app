import SwiftUI
import FlipcashUI

/// Standalone DEBUG demo: a tilt-reactive gold bar with on-device tuning sliders.
struct GoldBarDemoScreen: View {

    @Environment(\.dismiss) private var dismiss

    @State private var lightIntensity: Double = 1100
    @State private var environmentIntensity: Double = 4.8
    @State private var relief: Double = 0.55

    private let qrPayload = "https://flipcash.com/gold-bar-demo"

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.04).ignoresSafeArea()

                GoldBarSceneView(
                    qrPayload: qrPayload,
                    lightIntensity: lightIntensity,
                    environmentIntensity: environmentIntensity,
                    relief: relief
                )
                .aspectRatio(0.60 / 1.04, contentMode: .fit)
                .padding(.horizontal, 16)

                VStack {
                    Spacer()
                    GoldBarTuningPanel(
                        lightIntensity: $lightIntensity,
                        environmentIntensity: $environmentIntensity,
                        relief: $relief
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
        }
    }
}

/// On-device tuning controls. Extracted as a struct (no view functions / computed view properties).
private struct GoldBarTuningPanel: View {
    @Binding var lightIntensity: Double
    @Binding var environmentIntensity: Double
    @Binding var relief: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledSlider(title: "Light", value: $lightIntensity, range: 0...2500)
            LabeledSlider(title: "Environment", value: $environmentIntensity, range: 0...8)
            LabeledSlider(title: "Relief", value: $relief, range: 0...2)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(title)
                .font(.appTextHeading)
                .foregroundStyle(.textSecondary)
                .frame(width: 110, alignment: .leading)
            Slider(value: $value, in: range)
        }
    }
}
