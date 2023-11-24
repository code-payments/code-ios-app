//
//  Chart.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct Chart: View {
    
    @Binding public var selectedIndexes: [Int]
    
    public let dataSet: DataSet
    public let smooth: Bool
    public let interactive: Bool
    public let style: Style
    public let annotation: Annotation?
    
    // MARK: - Init -
    
    public init(dataSet: DataSet, smooth: Bool, interactive: Bool, selectedIndexes: Binding<[Int]> = .constant([]), style: Style = Style(), annotation: Annotation? = nil) {
        self.dataSet          = dataSet
        self.smooth           = smooth
        self.interactive      = interactive
        self.style            = style
        self.annotation       = annotation
        self._selectedIndexes = selectedIndexes
    }
    
    public var body: some View {
        GeometryReader { geometry in
            if let baseline = dataSet.normalizedBaseline {
                LineShape(normalizedPoints: [baseline, baseline], smooth: smooth)
                    .stroke(style: StrokeStyle(
                        lineWidth: style.baselineWidth,
                        lineCap: .square,
                        lineJoin: .round,
                        dash: style.baselineDash,
                        dashPhase: style.baselinePhase
                    ))
                    .foregroundColor(style.baselineColor)
                    .offset(x: 0, y: dataSet.yOffset(in: geometry))
            }
            HStack(spacing: 4) {
                ZStack {
                    LineShape(normalizedPoints: dataSet.normalizedPoints, smooth: smooth)
                        .stroke(style: StrokeStyle(
                            lineWidth: style.lineWidth,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: style.lineDash,
                            dashPhase: style.linePhase
                        ))
                        .foregroundColor(style.lineColor)
                        .offset(x: 0, y: dataSet.yOffset(in: geometry))
                    if interactive {
                        InteractiveOverlay(dataSet: dataSet, selectedIndexes: $selectedIndexes)
                    }
                }
                
                if let annotation = annotation, let lastNormalizedPoint = dataSet.normalizedPoints.last {
                    ValueAnnotation(
                        text: annotation.stringValue,
                        normalizedValue: lastNormalizedPoint,
                        geometry: geometry,
                        positionBelow: dataSet.trend == .negative
                    )
                    .offset(x: 0, y: dataSet.yOffset(in: geometry))
                }
            }
        }
    }
}

// MARK: - Style -

extension Chart {
    public struct Style {
        
        var lineWidth: CGFloat
        var lineDash: [CGFloat]
        var linePhase: CGFloat
        var lineColor: Color
        var baselineWidth: CGFloat
        var baselineDash: [CGFloat]
        var baselinePhase: CGFloat
        var baselineColor: Color
        
        public init(
            lineWidth: CGFloat = 1,
            lineDash: [CGFloat] = [],
            linePhase: CGFloat = 0,
            lineColor: Color = .red,
            baselineWidth: CGFloat = 1,
            baselineDash: [CGFloat] = [4, 3],
            baselinePhase: CGFloat = 0,
            baselineColor: Color = .black.opacity(0.2)
        ) {
            self.lineWidth = lineWidth
            self.lineDash = lineDash
            self.linePhase = linePhase
            self.lineColor = lineColor
            self.baselineWidth = baselineWidth
            self.baselineDash = baselineDash
            self.baselinePhase = baselinePhase
            self.baselineColor = baselineColor
        }
    }
}

// MARK: - Annotation -

extension Chart {
    public struct Annotation {
        
        public var value: String
        public var prefix: String
        public var suffix: String
        
        public init(value: String, prefix: String = "", suffix: String = "") {
            self.value  = value
            self.prefix = prefix
            self.suffix = suffix
        }
        
        public init(value: Decimal, formatter: NumberFormatter, prefix: String = "", suffix: String = "") {
            self.value  = formatter.string(from: value)!
            self.prefix = prefix
            self.suffix = suffix
        }
        
        public var stringValue: String {
            "\(prefix)\(value)\(suffix)"
        }
    }
}

// MARK: - InteractiveOverlay -

struct InteractiveOverlay: View {
    
    let dataSet: DataSet
    
    @Binding var selectedIndexes: [Int]
    
    @State private var touches: [Touch] = []
    
//    @State private var touches: [Touch] = [
//        Touch(
//            location: CGPoint(x: 130, y: 50),
//            tapCount: 1,
//            timestamp: 0
//        )
//    ]
    
    private let scrubberSize: CGFloat = 16
    
    init(dataSet: DataSet, selectedIndexes: Binding<[Int]>) {
        self.dataSet = dataSet
        self._selectedIndexes = selectedIndexes
    }
    
    var body: some View {
        ZStack {
            if dataSet.count > 1 {
                MultitouchView(maxTouches: 2, touches: $touches)
                GeometryReader { geometry in
                    ForEach(0..<touches.count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 99)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 2)
                            .position(CGPoint(
                                x: positionForTouch(touches[index], in: geometry).x,
                                y: geometry.size.height * 0.5
                            ))
                    }
                    ForEach(0..<touches.count, id: \.self) { index in
                        ZStack {
                            Circle()
                                .fill(Color.backgroundMain)
                            Circle()
                                .fill(Color.chartLine)
                                .padding(scrubberSize - floor(scrubberSize * 0.88))
                        }
                        .frame(width: scrubberSize, height: scrubberSize)
                        .position(positionForTouch(touches[index], in: geometry))
                    }
                    EmptyView()
                        .onChange(of: touches) { touches in
                            selectedIndexes = touches.map {
                                indexForTouch($0, in: geometry)
                            }
                        }
                }
            }
        }
    }
    
    private func indexForTouch(_ touch: Touch, in geometry: GeometryProxy) -> Int {
        guard let interval = dataSet.xInterval(in: geometry.size.width) else {
            return 0
        }
        
        // Compute the index after offsetting touch inputs
        // by half-interval to center point selection
        var index = Int((touch.location.x + (interval * 0.5)) / interval)
        
        // Clamp the index after adjusting touch inputs
        index = max(min(index, dataSet.normalizedPoints.count - 1), 0)
        
        return index
    }
    
    private func positionForTouch(_ touch: Touch, in geometry: GeometryProxy) -> CGPoint {
        let i = indexForTouch(touch, in: geometry)
        let x = CGFloat(i) * (dataSet.xInterval(in: geometry.size.width) ?? 0)
        let y = geometry.size.height - (CGFloat(dataSet.normalizedPoints[i]) * geometry.size.height) + dataSet.yOffset(in: geometry)
        
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Previews -

struct Chart_Previews: PreviewProvider {
    
    static let style: Chart.Style = .init(
        lineWidth: 3.0,
        lineColor: .chartLine,
        baselineWidth: 1.5,
        baselineDash: [2, 5],
        baselineColor: .white.opacity(0.3)
    )
    
    static var previews: some View {
        Group {
            Chart(
                dataSet: dataSet(dip: false),
                smooth: true,
                interactive: false,
                style: style
            )
            
            Chart(
                dataSet: dataSet(dip: true),
                smooth: false,
                interactive: true,
                style: style
            )
            
            Chart(
                dataSet: emptyDataSet(),
                smooth: true,
                interactive: false,
                style: style
            )
            
            Chart(
                dataSet: minimumHeightDataSet(),
                smooth: false,
                interactive: true,
                style: style
            )
        }
        .background(Color.backgroundMain)
        .previewLayout(.fixed(width: 300, height: 100))
    }
}

extension Chart_Previews {
    
    static func emptyDataSet(baseline: Double = 0) -> DataSet {
         DataSet(
            points: [0],
            baseline: baseline
        )
    }
    
    static func dataSet(reverse: Bool = false, baseline: Double = 50, dip: Bool = false) -> DataSet {
        var points: [Double] = [
            10, 30, 20, 40, 30, 40, 50, 60, 25, 50, 90, 70, 80, 90, 70, 50, 40, dip ? 45 : 55,
        ]
        
        if reverse {
            points.reverse()
        }
        
        return DataSet(
            points: points,
            baseline: baseline
        )
    }
    
    static func minimumHeightDataSet() -> DataSet {
        DataSet(
            points: [
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -0.9,
            ],
            baseline: 0,
            minimumHeight: 5
        )
    }
}

#endif
