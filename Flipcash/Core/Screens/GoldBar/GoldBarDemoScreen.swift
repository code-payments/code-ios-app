import SwiftUI
import FlipcashCore
import FlipcashUI

/// Standalone demo: a tilt-reactive gold bar with a floating PiP-style tuning panel.
struct GoldBarDemoScreen: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    @State private var tuning = GoldBarTuning.standard

    /// Preheat this key at the presenting tap (as `showCashBill` does for bills)
    /// so the demo opens with the bake already done.
    static let demoKey = GoldBarTextureStore.Key(
        payload: .placeholder35,
        stampLines: ["$25.00"],
        serial: PublicKey.usdf.base58
    )

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.04).ignoresSafeArea()

                GoldBarView(key: Self.demoKey, tuning: tuning)

                GoldBarTuningOverlay(tuning: $tuning)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
            .onChange(of: session.isShowingBill) { _, isShowingBill in
                // One pooled SCNView — a presenting bill takes it, so the demo
                // steps aside instead of showing an empty stage.
                if isShowingBill { dismiss() }
            }
        }
    }
}

/// Owns the floating panel's position so drags re-render only this overlay, never the scene view.
/// Mirrors system PiP: 1:1 drag from anywhere on the panel, momentum snap to the nearest corner
/// on release. The panel always stays fully on screen.
private struct GoldBarTuningOverlay: View {
    @Binding var tuning: GoldBarTuning

    @State private var position: CGPoint?
    @State private var panelSize = CGSize(width: 300, height: 320)
    @State private var dragStart: CGPoint?

    private let margin: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let current = position ?? restingPosition(in: geo.size)
            GoldBarTuningPanel(tuning: $tuning)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { panelSize = $0 }
            .gesture(dragGesture(from: current, in: geo.size))
            .position(current)
        }
    }

    /// Measured in global space: the panel moves with the finger, so a local-space
    /// translation would oscillate against the moving view and glitch.
    private func dragGesture(from current: CGPoint, in container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? current
                dragStart = start
                position = CGPoint(x: start.x + value.translation.width,
                                   y: start.y + value.translation.height)
            }
            .onEnded { value in
                let start = dragStart ?? current
                dragStart = nil
                let projected = CGPoint(x: start.x + value.predictedEndTranslation.width,
                                        y: start.y + value.predictedEndTranslation.height)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                    position = nearestCorner(to: projected, in: container)
                }
            }
    }

    private func restingPosition(in container: CGSize) -> CGPoint {
        CGPoint(x: container.width / 2, y: container.height - panelSize.height / 2 - margin)
    }

    private func nearestCorner(to point: CGPoint, in container: CGSize) -> CGPoint {
        let x = point.x < container.width / 2
            ? margin + panelSize.width / 2
            : container.width - margin - panelSize.width / 2
        let y = point.y < container.height / 2
            ? margin + panelSize.height / 2
            : container.height - margin - panelSize.height / 2
        return CGPoint(x: x, y: y)
    }
}

private struct GoldBarTuningPanel: View {
    @Binding var tuning: GoldBarTuning

    var body: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            LabeledSlider(title: "Light", value: $tuning.lightIntensity, range: 0...2500)
            LabeledSlider(title: "Environment", value: $tuning.environmentIntensity, range: 0...8)
            LabeledSlider(title: "Relief", value: $tuning.relief, range: 0...2)
            LabeledSlider(title: "Light X", value: $tuning.lightAnchor.x, range: -1.5...1.5)
            LabeledSlider(title: "Light Y", value: $tuning.lightAnchor.y, range: -0.5...1.5)
            LabeledSlider(title: "Rotation X", value: $tuning.barRotationDegrees.x, range: -90...90)
            LabeledSlider(title: "Rotation Y", value: $tuning.barRotationDegrees.y, range: -90...90)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(width: 330)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
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
                .foregroundStyle(.textMain)
                .frame(width: 92, alignment: .leading)
            Slider(value: $value, in: range)
            Text(value, format: .number.precision(.fractionLength(0...2)))
                .font(.appTextHeading)
                .monospacedDigit()
                .foregroundStyle(.textMain)
                .frame(width: 52, alignment: .trailing)
        }
    }
}
