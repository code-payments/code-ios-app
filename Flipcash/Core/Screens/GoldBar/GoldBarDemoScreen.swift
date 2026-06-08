import SwiftUI
import FlipcashUI

/// Standalone DEBUG demo: a tilt-reactive gold bar with a draggable floating tuning panel.
struct GoldBarDemoScreen: View {

    @Environment(\.dismiss) private var dismiss

    @State private var lightIntensity: Double = 1100
    @State private var environmentIntensity: Double = 5.2
    @State private var relief: Double = 0.55
    @State private var panelOffset: CGSize = .zero
    @State private var panelLastOffset: CGSize = .zero

    private let qrPayload = "https://flipcash.com/gold-bar-demo"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(white: 0.04).ignoresSafeArea()

                GoldBarSceneView(
                    qrPayload: qrPayload,
                    lightIntensity: lightIntensity,
                    environmentIntensity: environmentIntensity,
                    relief: relief
                )
                .ignoresSafeArea()

                GoldBarTuningPanel(
                    lightIntensity: $lightIntensity,
                    environmentIntensity: $environmentIntensity,
                    relief: $relief,
                    offset: $panelOffset,
                    lastOffset: $panelLastOffset
                )
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
        }
    }
}

/// A draggable floating tuning panel (PiP-style). Drag the grab handle to move it anywhere.
private struct GoldBarTuningPanel: View {
    @Binding var lightIntensity: Double
    @Binding var environmentIntensity: Double
    @Binding var relief: Double
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    var body: some View {
        VStack(spacing: 10) {
            GrabHandle(offset: $offset, lastOffset: $lastOffset)
            LabeledSlider(title: "Light", value: $lightIntensity, range: 0...2500)
            LabeledSlider(title: "Environment", value: $environmentIntensity, range: 0...8)
            LabeledSlider(title: "Relief", value: $relief, range: 0...2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(width: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .offset(offset)
    }
}

/// Grab handle that drags the whole panel; isolated so the sliders keep their own gestures.
private struct GrabHandle: View {
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    var body: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
            )
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
                .frame(width: 100, alignment: .leading)
            Slider(value: $value, in: range)
        }
    }
}
