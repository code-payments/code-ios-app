import Charts
import SwiftUI

/// The main line chart view using Swift Charts
public struct ChartLineView: View {
    let dataPoints: [ChartDataPoint]
    let accentColor: Color
    let secondaryColor: Color
    let scrubbedPoint: ChartDataPoint?
    let isScrubbing: Bool
    let onScrubChange: ((Int) -> Void)?
    let onScrubEnd: (() -> Void)?
    
    public init(
        dataPoints: [ChartDataPoint],
        accentColor: Color,
        secondaryColor: Color,
        scrubbedPoint: ChartDataPoint? = nil,
        isScrubbing: Bool = false,
        onScrubChange: ((Int) -> Void)? = nil,
        onScrubEnd: (() -> Void)? = nil
    ) {
        self.dataPoints = dataPoints
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor
        self.scrubbedPoint = scrubbedPoint
        self.isScrubbing = isScrubbing
        self.onScrubChange = onScrubChange
        self.onScrubEnd = onScrubEnd
    }
    
    /// Data points to draw the line up to (all points when not scrubbing, up to scrubbed point when scrubbing)
    private var lineDataPoints: [ChartDataPoint] {
        guard isScrubbing, let scrubbed = scrubbedPoint else {
            return dataPoints
        }
        return dataPoints.filter { $0.id <= scrubbed.id }
    }
    
    public var body: some View {
        Chart {
            // Always-visible base line for context
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value("Position", point.normalizedPosition),
                    y: .value("Value", point.value),
                    series: .value("Line", "Baseline")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(secondaryColor)
                .lineStyle(.init(lineWidth: 3))
            }
            
            // Line mark only up to the current position (scrubbed point or end)
            ForEach(lineDataPoints) { point in
                LineMark(
                    x: .value("Position", point.normalizedPosition),
                    y: .value("Value", point.value),
                    series: .value("Line", "Active")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accentColor)
                .lineStyle(.init(lineWidth: 3))
            }
                        
            // Endpoint indicator
            if let lastPoint = dataPoints.last {
                PointMark(
                    x: .value("Position", lastPoint.normalizedPosition),
                    y: .value("Value", lastPoint.value)
                )
                .symbol {
                    ScrubIndicator(
                        backgroundColor: accentColor,
                        borderColor: isScrubbing ? secondaryColor : accentColor,
                        isBackgroundHidden: isScrubbing)
                }
            }
            
            // Scrubber indicator
            if let scrubbed = scrubbedPoint {
                PointMark(
                    x: .value("Position", scrubbed.normalizedPosition),
                    y: .value("Value", scrubbed.value)
                )
                .symbol {
                    ScrubIndicator(
                        backgroundColor: accentColor,
                        borderColor: accentColor,
                        isBackgroundHidden: false)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...1)
        .chartYScale(domain: yAxisDomain, type: .linear)
        .scrollDisabled(true)
        .background {
            AnimatableAreaGradient(
                color: accentColor,
                dataPoints: dataPoints,
                yAxisDomain: yAxisDomain
            )
        }
        .chartOverlay { proxy in
            LongPressGestureView(
                minimumDuration: 0.15,
                onBegan: { location in
                    handleScrub(at: location, proxy: proxy)
                    triggerSelectionHaptic(at: location)
                },
                onChanged: { location in
                    handleScrub(at: location, proxy: proxy)
                },
                onEnded: {
                    onScrubEnd?()
                }
            )
        }
    }
    
    /// Handles scrubbing by converting normalized position to point ID
    private func handleScrub(at location: CGPoint, proxy: ChartProxy) {
        if let normalizedX: Double = proxy.value(atX: location.x) {
            // Find the closest data point by normalized position
            if let closest = dataPoints.min(by: {
                abs($0.normalizedPosition - normalizedX) < abs($1.normalizedPosition - normalizedX)
            }) {
                onScrubChange?(closest.id)
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
    
    private func triggerSelectionHaptic(at location: CGPoint) {
        let generator = UISelectionFeedbackGenerator()
        if #available(iOS 17.5, *) {
            generator.selectionChanged(at: location)
        } else {
            // Fallback on earlier versions
            generator.selectionChanged()
        }
    }
}

#Preview {
    let count = 30
    let points = (0..<count).map { i in
        ChartDataPoint(
            id: i,
            date: Date().addingTimeInterval(TimeInterval(i * 86400)),
            value: Double.random(in: 100...150),
            normalizedPosition: Double(i) / Double(count - 1)
        )
    }
    
    return ChartLineView(
        dataPoints: points,
        accentColor: .green,
        secondaryColor: .mint,
        scrubbedPoint: points[15]
    )
    .frame(height: 200)
    .padding()
}

// MARK: - Animatable Area Gradient

/// Draws a gradient that's masked to the chart area shape and animates color changes
private struct AnimatableAreaGradient: View {
    let color: Color
    let dataPoints: [ChartDataPoint]
    let yAxisDomain: ClosedRange<Double>
    
    var body: some View {
        // Gradient rectangle masked by the area shape
        LinearGradient(
            colors: [
                color.opacity(0.25),
                color.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .mask {
            // Use a chart as the mask shape
            Chart {
                ForEach(dataPoints) { point in
                    AreaMark(
                        x: .value("Position", point.normalizedPosition),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartXScale(domain: 0...1)
            .chartYScale(domain: yAxisDomain, type: .linear)
        }
    }
}

// MARK: - Custom Scrub Indicator

private struct ScrubIndicator: View {
    let backgroundColor: Color
    let borderColor: Color
    var isBackgroundHidden: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 20, height: 20)
                .opacity(isBackgroundHidden ? 0 : 0.2)

            Circle()
                .fill(backgroundColor.mixed(with: .black, by: 0.35))
                .stroke(borderColor, lineWidth: 2)
                .frame(width: 10, height: 10)
        }
    }
}

// MARK: - Long Press Gesture View

/// A UIKit-based long press gesture that provides location and doesn't hijack scroll
private struct LongPressGestureView: UIViewRepresentable {
    let minimumDuration: TimeInterval
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let gesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleGesture(_:))
        )
        gesture.minimumPressDuration = minimumDuration
        gesture.delegate = context.coordinator
        view.addGestureRecognizer(gesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onBegan: (CGPoint) -> Void
        let onChanged: (CGPoint) -> Void
        let onEnded: () -> Void
        private weak var scrollView: UIScrollView?
        
        init(
            onBegan: @escaping (CGPoint) -> Void,
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }
        
        @objc func handleGesture(_ gesture: UILongPressGestureRecognizer) {
            let location = gesture.location(in: gesture.view)

            switch gesture.state {
            case .began:
                scrollView = gesture.view?.nearestScrollView()
                scrollView?.panGestureRecognizer.isEnabled = false
                scrollView?.panGestureRecognizer.isEnabled = true // reset if it was mid-gesture
                onBegan(location)

            case .changed:
                onChanged(location)

            case .ended, .cancelled, .failed:
                // Re-enable scrolling
                scrollView?.panGestureRecognizer.isEnabled = true
                onEnded()

            default:
                break
            }
        }
        
        // Allow scroll view to work simultaneously until long press is recognized.
        // It is important to disable the contentSwipe gesture and sheet dismissal so it doesn't interfer with
        // the user scrubbing the chart
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return otherGestureRecognizer.name != "UINavigationController.contentSwipe" && otherGestureRecognizer.name != "_UISheetInteractionBackgroundDismissRecognizer"
        }
    }
}

private extension UIView {
    func nearestScrollView() -> UIScrollView? {
        var v: UIView? = self
        while let cur = v {
            if let sv = cur as? UIScrollView { return sv }
            v = cur.superview
        }
        return nil
    }
}
