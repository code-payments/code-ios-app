import SwiftUI
import FlipcashCore
import FlipcashUI

/// Standalone DEBUG demo: a tilt-reactive gold bar with a floating PiP-style tuning panel.
struct GoldBarDemoScreen: View {

    @Environment(\.dismiss) private var dismiss

    @State private var lightIntensity: Double = GoldBarScene.defaultLightIntensity
    @State private var environmentIntensity: Double = GoldBarScene.defaultEnvironmentIntensity
    @State private var relief: Double = GoldBarScene.defaultRelief
    @State private var lightX: Double = GoldBarLighting.restAnchor.x
    @State private var lightY: Double = GoldBarLighting.restAnchor.y
    @State private var barRotationX: Double = 0
    @State private var barRotationY: Double = 0
    @State private var isSceneReady = false

    private let codeData = Data.placeholder35

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.04).ignoresSafeArea()

                GoldBarSceneView(
                    codeData: codeData,
                    stampLines: ["$25.00"],
                    serial: PublicKey.usdf.base58,
                    lightIntensity: lightIntensity,
                    environmentIntensity: environmentIntensity,
                    relief: relief,
                    lightAnchor: SIMD2(lightX, lightY),
                    barRotationDegrees: SIMD2(barRotationX, barRotationY),
                    onSceneReady: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isSceneReady = true
                        }
                    }
                )
                .ignoresSafeArea()

                GoldBarPlaceholder()
                    .opacity(isSceneReady ? 0 : 1)
                    .allowsHitTesting(false)

                GoldBarTuningOverlay(
                    lightIntensity: $lightIntensity,
                    environmentIntensity: $environmentIntensity,
                    relief: $relief,
                    lightX: $lightX,
                    lightY: $lightY,
                    barRotationX: $barRotationX,
                    barRotationY: $barRotationY
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
        }
    }
}

/// Flat gold stand-in shown while SceneKit compiles the scene off the main thread.
/// Sized and positioned to match the rendered bar so the crossfade doesn't jump.
struct GoldBarPlaceholder: View {
    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height * 0.80
            let width = height * (0.60 / 1.04)
            RoundedRectangle(cornerRadius: height * 0.021)
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
        .ignoresSafeArea()
    }
}

/// Owns the floating panel's position so drags re-render only this overlay, never the scene view.
/// Mirrors system PiP: 1:1 drag from anywhere on the panel, momentum snap to the nearest corner
/// on release, and a fling past a screen edge stashes the panel with a tab peeking; tap to restore.
private struct GoldBarTuningOverlay: View {
    @Binding var lightIntensity: Double
    @Binding var environmentIntensity: Double
    @Binding var relief: Double
    @Binding var lightX: Double
    @Binding var lightY: Double
    @Binding var barRotationX: Double
    @Binding var barRotationY: Double

    @State private var position: CGPoint?
    @State private var panelSize = CGSize(width: 300, height: 320)
    @State private var dragStart: CGPoint?
    @State private var isStashed = false

    private let margin: CGFloat = 12
    private let stashPeek: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let current = position ?? restingPosition(in: geo.size)
            GoldBarTuningPanel(
                lightIntensity: $lightIntensity,
                environmentIntensity: $environmentIntensity,
                relief: $relief,
                lightX: $lightX,
                lightY: $lightY,
                barRotationX: $barRotationX,
                barRotationY: $barRotationY
            )
            .onGeometryChange(for: CGSize.self) { $0.size } action: { panelSize = $0 }
            .onTapGesture {
                guard isStashed else { return }
                isStashed = false
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                    position = nearestCorner(to: current, in: geo.size)
                }
            }
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
                let stashedEdge = stashEdge(for: projected, in: container)
                isStashed = stashedEdge != nil
                let target = stashedEdge.map { stashPosition(edge: $0, y: projected.y, in: container) }
                    ?? nearestCorner(to: projected, in: container)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                    position = target
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

    /// A fling whose projected center crosses a vertical screen edge stashes the panel there.
    private func stashEdge(for projected: CGPoint, in container: CGSize) -> HorizontalEdge? {
        if projected.x < 0 { return .leading }
        if projected.x > container.width { return .trailing }
        return nil
    }

    private func stashPosition(edge: HorizontalEdge, y: CGFloat, in container: CGSize) -> CGPoint {
        let x: CGFloat = switch edge {
        case .leading: -panelSize.width / 2 + stashPeek
        case .trailing: container.width + panelSize.width / 2 - stashPeek
        }
        let minY = margin + panelSize.height / 2
        let maxY = container.height - margin - panelSize.height / 2
        return CGPoint(x: x, y: min(max(y, minY), maxY))
    }

    private enum HorizontalEdge {
        case leading, trailing
    }
}

private struct GoldBarTuningPanel: View {
    @Binding var lightIntensity: Double
    @Binding var environmentIntensity: Double
    @Binding var relief: Double
    @Binding var lightX: Double
    @Binding var lightY: Double
    @Binding var barRotationX: Double
    @Binding var barRotationY: Double

    var body: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            LabeledSlider(title: "Light", value: $lightIntensity, range: 0...2500)
            LabeledSlider(title: "Environment", value: $environmentIntensity, range: 0...8)
            LabeledSlider(title: "Relief", value: $relief, range: 0...2)
            LabeledSlider(title: "Light X", value: $lightX, range: -1.5...1.5)
            LabeledSlider(title: "Light Y", value: $lightY, range: -0.5...1.5)
            LabeledSlider(title: "Rotation X", value: $barRotationX, range: -90...90)
            LabeledSlider(title: "Rotation Y", value: $barRotationY, range: -90...90)
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
