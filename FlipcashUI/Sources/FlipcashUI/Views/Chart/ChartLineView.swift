import Charts
import SwiftUI

/// The main line chart view using Swift Charts
public struct ChartLineView: View {
    let dataPoints: [ChartDataPoint]
    let accentColor: Color
    let scrubbedPoint: ChartDataPoint?
    let isScrubbing: Bool
    let onScrubChange: ((Date) -> Void)?
    let onScrubEnd: (() -> Void)?
    
    /// Unique identifier for the current data set to force fresh renders
    private var dataIdentifier: String {
        guard let first = dataPoints.first, let last = dataPoints.last else { return "empty" }
        return "\(first.date.timeIntervalSince1970)-\(last.date.timeIntervalSince1970)-\(dataPoints.count)"
    }
    
    public init(
        dataPoints: [ChartDataPoint],
        accentColor: Color,
        scrubbedPoint: ChartDataPoint? = nil,
        isScrubbing: Bool = false,
        onScrubChange: ((Date) -> Void)? = nil,
        onScrubEnd: (() -> Void)? = nil
    ) {
        self.dataPoints = dataPoints
        self.accentColor = accentColor
        self.scrubbedPoint = scrubbedPoint
        self.isScrubbing = isScrubbing
        self.onScrubChange = onScrubChange
        self.onScrubEnd = onScrubEnd
    }
    
    public var body: some View {
        Chart {
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accentColor)
                
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.3),
                            accentColor.opacity(0.1),
                            accentColor.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            
            // Endpoint indicator (hidden when scrubbing)
            if !isScrubbing, let lastPoint = dataPoints.last {
                PointMark(
                    x: .value("Date", lastPoint.date),
                    y: .value("Value", lastPoint.value)
                )
                .foregroundStyle(accentColor)
                .symbolSize(60)
            }
            
            // Scrubber indicator
            if let scrubbed = scrubbedPoint {
                RuleMark(x: .value("Date", scrubbed.date))
                    .foregroundStyle(accentColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                
                PointMark(
                    x: .value("Date", scrubbed.date),
                    y: .value("Value", scrubbed.value)
                )
                .foregroundStyle(accentColor)
                .symbolSize(80)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: yAxisDomain)
        .id(dataIdentifier)
        .scrollDisabled(true)
        .chartGesture { proxy in
            // This value prevents the Chart from stealing the touch event of the parent ScrollView
            DragGesture(minimumDistance: 25)
                .onChanged { value in
                    if let date: Date = proxy.value(atX: value.location.x) {
                        onScrubChange?(date)
                        triggerSelectionHaptic()
                    }
                }
                .onEnded { _ in
                    onScrubEnd?()
                }
        }
    }
    
    /// Calculates a padded Y-axis domain for better visualization
    private var yAxisDomain: ClosedRange<Double> {
        guard let minValue = dataPoints.map(\.value).min(),
              let maxValue = dataPoints.map(\.value).max() else {
            return 0...100
        }
        
        let padding = (maxValue - minValue) * 0.1
        return (minValue - padding)...(maxValue + padding)
    }
    
    private func triggerSelectionHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

#Preview {
    let points = (0..<30).map { i in
        ChartDataPoint(
            date: Date().addingTimeInterval(TimeInterval(i * 86400)),
            value: Double.random(in: 100...150)
        )
    }
    
    return ChartLineView(
        dataPoints: points,
        accentColor: .green,
        scrubbedPoint: points[15]
    )
    .frame(height: 200)
    .padding()
}
