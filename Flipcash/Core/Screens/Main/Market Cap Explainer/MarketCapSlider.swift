//
//  MarketCapSlider.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A continuous slider over the log-reserve track with labeled tick marks.
/// Ticks are reference marks, not snap points.
struct MarketCapSlider: View {
    @Binding var position: Double
    let ticks: [Tick]

    struct Tick: Identifiable {
        let id: Decimal
        let position: Double
        let label: String?
        var isToday: Bool = false
    }

    // Slider v2 (node 10761:2119): 10pt track, thumb centered on it,
    // ticks 5pt below the track, labels under the ticks.
    private let thumbHeight: CGFloat = 24
    private let trackHeight: CGFloat = 10
    private let trackTop: CGFloat = 15
    private let areaHeight: CGFloat = 60

    private static let trackColor = Color(red: 71 / 255, green: 71 / 255, blue: 72 / 255)
    private static let fillColor = MarketCapExplainerPalette.green
    private static let labelGap: CGFloat = 6

    /// True while a finger is down; drives the thumb's pressed state.
    @GestureState private var isPressed = false

    /// Measured width of each label, keyed by tick.
    @State private var labelWidths: [Decimal: CGFloat] = [:]

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Self.trackColor)
                    .frame(width: width, height: trackHeight)
                    .offset(y: trackTop)

                Capsule()
                    .fill(Self.fillColor)
                    .frame(width: width * position, height: trackHeight)
                    .offset(y: trackTop)

                let labels = labelLayout(width: width)
                ForEach(ticks) { tick in
                    tickView(tick)
                        .position(
                            x: width * tick.position,
                            y: (tick.isToday ? 28 : 30) + (tick.isToday ? 10 : 6) / 2
                        )
                    if let label = tick.label {
                        labelText(label, tick: tick)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured in
                                if labelWidths[tick.id] != measured { labelWidths[tick.id] = measured }
                            }
                            .position(x: 0, y: 44 + 7)
                        if let x = labels[tick.id] {
                            labelText(label, tick: tick)
                                .position(x: x, y: 44 + 7)
                        }
                    }
                }

                thumb
                    .position(x: width * position, y: trackTop + trackHeight / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, pressed, _ in pressed = true }
                    .onChanged { drag in
                        position = min(max(drag.location.x / width, 0), 1)
                    }
                    .onEnded { _ in
                        guard let today = ticks.first(where: \.isToday) else { return }
                        withAnimation(.spring(duration: 0.4)) { position = today.position }
                    }
            )
        }
        .frame(height: areaHeight)
        .sensoryFeedback(.impact(weight: .light), trigger: crossedTickCount)
        .accessibilityElement()
        .accessibilityLabel("Amount purchased by the community")
        .accessibilityValue("\(Int(position * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: position = min(position + 0.05, 1)
            case .decrement: position = max(position - 0.05, 0)
            @unknown default: break
            }
        }
    }

    /// Mirrors the system slider thumb: on iOS 26 a white capsule that turns to
    /// Liquid Glass and grows while pressed, before that the classic 28pt disc.
    @ViewBuilder
    private var thumb: some View {
        if #available(iOS 26, *) {
            ZStack {
                if isPressed {
                    Capsule().fill(Color.clear)
                        .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Capsule().fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                }
            }
            .frame(width: 38, height: thumbHeight)
            .scaleEffect(isPressed ? 1.5 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: isPressed)
        } else {
            Circle().fill(Color.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        }
    }

    private func labelText(_ label: String, tick: Tick) -> some View {
        Text(label)
            .font(.appTextCaption)
            .fontWeight(tick.isToday ? .bold : .medium)
            .foregroundStyle(tick.isToday ? Color.textMain : Color.textSecondary)
            .fixedSize()
    }

    /// Center x for each label that gets drawn, from measured widths. Labels are
    /// clamped inside the track, Today always draws, and a fixed label whose frame
    /// would come within `labelGap` of one already drawn is dropped (its tick stays).
    private func labelLayout(width: CGFloat) -> [Decimal: CGFloat] {
        func frame(_ tick: Tick) -> (center: CGFloat, half: CGFloat)? {
            guard let measured = labelWidths[tick.id] else { return nil }
            let half = measured / 2
            return (min(max(width * tick.position, half), max(width - half, half)), half)
        }
        var drawn: [(center: CGFloat, half: CGFloat)] = []
        var result: [Decimal: CGFloat] = [:]
        let ordered = ticks.filter { $0.label != nil }.sorted { $0.isToday && !$1.isToday }
        for tick in ordered {
            guard let f = frame(tick) else { continue }
            let collides = drawn.contains { abs($0.center - f.center) < $0.half + f.half + Self.labelGap }
            if collides && !tick.isToday { continue }
            drawn.append(f)
            result[tick.id] = f.center
        }
        return result
    }

    /// Changes each time the thumb crosses a tick, which fires the haptic.
    private var crossedTickCount: Int {
        ticks.filter { $0.position < position }.count
    }

    private func tickView(_ tick: Tick) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(tick.isToday ? Color.textMain : Color.textSecondary.opacity(0.6))
            .frame(width: 2, height: tick.isToday ? 10 : 6)
    }
}
