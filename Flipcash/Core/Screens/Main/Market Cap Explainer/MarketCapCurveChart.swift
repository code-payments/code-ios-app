//
//  MarketCapCurveChart.swift
//  Flipcash
//

import SwiftUI
import Charts
import FlipcashCore
import FlipcashUI

/// The bonding curve: solid with a fade beneath it up to the selected supply,
/// dashed beyond, a reference line at Today's price, and a marker at the selection.
struct MarketCapCurveChart: View, Animatable {
    let explainer: MarketCapExplainer
    /// The slider position in 0...1. Animatable, so a spring on the slider
    /// re-renders the chart from the real selection each frame instead of
    /// Charts interpolating between two data sets of different sizes.
    var position: Double
    let reserveText: (Decimal) -> String

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    /// Everything derived from one position, computed once per render.
    struct Frame {
        let selection: MarketCapExplainer.Stop
        let today: MarketCapExplainer.Stop
        let points: [MarketCapExplainer.CurvePoint]
        let xDomain: ClosedRange<Double>
        let yRange: ClosedRange<Double>
        let selectionLabel: String

        init(explainer: MarketCapExplainer, position: Double, reserveText: (Decimal) -> String) {
            selection = explainer.stop(atTrackPosition: position)
            today = explainer.todayStop
            points = explainer.curvePoints(for: selection)
            xDomain = explainer.chartXDomain(for: selection)
            yRange = explainer.chartPriceRange(for: selection)
            selectionLabel = selection.isToday
                ? "\(reserveText(selection.reserve)) Today"
                : reserveText(selection.reserve)
        }

        var selectedX: Double { selection.supply.doubleValue }
        var selectedY: Double { selection.price.doubleValue }
        var todayX: Double { today.supply.doubleValue }
        var todayY: Double { today.price.doubleValue }

        var solid: [MarketCapExplainer.CurvePoint] {
            points.filter { $0.supply < selectedX } + [.init(supply: selectedX, price: selectedY)]
        }

        var faded: [MarketCapExplainer.CurvePoint] {
            [.init(supply: selectedX, price: selectedY)] + points.filter { $0.supply > selectedX }
        }
    }

    var body: some View {
        chart(Frame(explainer: explainer, position: position, reserveText: reserveText))
    }

    private func chart(_ f: Frame) -> some View {
        Chart {
            ForEach(Array(f.solid.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Supply", point.supply),
                    yStart: .value("Floor", f.yRange.lowerBound),
                    yEnd: .value("Price", point.price),
                    series: .value("Series", "area")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.Sentiment.positive.opacity(0.35), Color.Sentiment.positive.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Supply", point.supply),
                    y: .value("Price", point.price),
                    series: .value("Series", "solid")
                )
                .foregroundStyle(Color.Sentiment.positive)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }

            ForEach(Array(f.faded.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Supply", point.supply),
                    y: .value("Price", point.price),
                    series: .value("Series", "faded")
                )
                .foregroundStyle(Color.Sentiment.positive.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
            }

            RuleMark(y: .value("Today's price", f.todayY))
                .foregroundStyle(Color.textSecondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            RuleMark(x: .value("Selected supply", f.selectedX))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(
                    position: .top,
                    alignment: .center,
                    spacing: 4,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    Text(f.selectionLabel)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textMain)
                        .fixedSize()
                }

            // Today sits past the right edge when the selection is far below it.
            if f.xDomain.contains(f.todayX) {
                PointMark(x: .value("Today", f.todayX), y: .value("Today's price", f.todayY))
                    .symbolSize(30)
                    .foregroundStyle(Color.textSecondary)
            }

            PointMark(x: .value("Selected supply", f.selectedX), y: .value("Price", f.selectedY))
                .symbolSize(180)
                .foregroundStyle(Color.Sentiment.positive)
        }
        .chartXScale(domain: f.xDomain)
        .chartYScale(domain: f.yRange)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.padding(.top, 28).padding(.horizontal, 8) }
        .frame(height: 220)
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }
}
