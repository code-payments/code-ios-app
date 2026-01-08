import Charts
import SwiftUI

/// The main line chart view using Swift Charts
public struct ChartLineView: View {
    let dataPoints: [ChartDataPoint]
    let accentColor: Color
    let scrubbedPoint: ChartDataPoint?
    let isScrubbing: Bool
    let onScrubChange: ((Int) -> Void)?
    let onScrubEnd: (() -> Void)?
    
    public init(
        dataPoints: [ChartDataPoint],
        accentColor: Color,
        scrubbedPoint: ChartDataPoint? = nil,
        isScrubbing: Bool = false,
        onScrubChange: ((Int) -> Void)? = nil,
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
                    x: .value("Position", point.normalizedPosition),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accentColor)
                
                AreaMark(
                    x: .value("Position", point.normalizedPosition),
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
                    x: .value("Position", lastPoint.normalizedPosition),
                    y: .value("Value", lastPoint.value)
                )
                .foregroundStyle(accentColor)
                .symbolSize(60)
            }
            
            // Scrubber indicator
            if let scrubbed = scrubbedPoint {
                RuleMark(x: .value("Position", scrubbed.normalizedPosition))
                    .foregroundStyle(accentColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                
                PointMark(
                    x: .value("Position", scrubbed.normalizedPosition),
                    y: .value("Value", scrubbed.value)
                )
                .foregroundStyle(accentColor)
                .symbolSize(80)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...1)
        .chartYScale(domain: yAxisDomain, type: .linear)
        .scrollDisabled(true)
        .chartOverlay { proxy in
            LongPressGestureView(
                minimumDuration: 0.15,
                onBegan: { location in
                    handleScrub(at: location, proxy: proxy)
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
                triggerSelectionHaptic()
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
        scrubbedPoint: points[15]
    )
    .frame(height: 200)
    .padding()
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
