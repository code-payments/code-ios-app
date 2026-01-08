import SwiftUI

/// A stock-style chart component with scrubbing and range selection
public struct StockChart: View {
    @State private var viewModel: ChartViewModel
    
    private let accentColor: Color
    private let valueFormatter: (Double) -> String
    private let dateFormatter: (Date) -> String
    
    /// Creates a stock chart with random data between start and end values
    /// - Parameters:
    ///   - startValue: The starting value for the data range
    ///   - endValue: The ending value for the data range
    ///   - selectedRange: The initial time range selection (defaults to .all)
    ///   - accentColor: The chart line and accent color
    ///   - valueFormatter: Optional custom formatter for displaying values
    ///   - dateFormatter: Optional custom formatter for displaying dates
    public init(
        startValue: Double,
        endValue: Double,
        selectedRange: ChartRange = .all,
        accentColor: Color = .green,
        valueFormatter: ((Double) -> String)? = nil,
        dateFormatter: ((Date) -> String)? = nil
    ) {
        self._viewModel = State(
            wrappedValue: ChartViewModel(
                startValue: startValue,
                endValue: endValue,
                selectedRange: selectedRange
            )
        )
        self.accentColor = accentColor
        self.valueFormatter = valueFormatter ?? { value in
            String(format: "$%.2f", value)
        }
        self.dateFormatter = dateFormatter ?? { date in
            date.formatted(date: .abbreviated, time: .omitted)
        }
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            headerView
                .padding(.horizontal, 20)
            
            // Full screen width, no padding
            chartView
            
            ChartRangePicker(
                selectedRange: Binding(
                    get: { viewModel.selectedRange },
                    set: { range in
                        withAnimation(.easeInOut(duration: 0.35)) {
                            viewModel.selectRange(range)
                        }
                    }
                ),
                accentColor: Color(r: 18, g: 42, b: 29) // FIXME: What is the Figma color?
            )
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(valueFormatter(viewModel.displayValue))
                .foregroundStyle(Color.textMain)
                .font(.appDisplayMedium)
                .contentTransition(.numericText())
            
            Text(changeText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(displayColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: viewModel.displayValue)
    }
    
    /// Formatted change text with context (e.g., "+ $17.52 all time")
    private var changeText: String {
        let change = viewModel.valueChange
        let prefix = change >= 0 ? "+ " : "- "
        let formatted = valueFormatter(abs(change))
        return "\(prefix)\(formatted) \(viewModel.selectedRange.contextLabel)"
    }
    
    private var chartView: some View {
        ChartLineView(
            dataPoints: viewModel.dataPoints,
            accentColor: displayColor,
            scrubbedPoint: viewModel.scrubbedPoint,
            isScrubbing: viewModel.isScrubbing,
            onScrubChange: { pointId in
                viewModel.updateScrub(pointId: pointId)
            },
            onScrubEnd: {
                viewModel.endScrub()
            }
        )
        .frame(height: 200)
    }
    
    // MARK: - Computed Properties
    
    private var displayColor: Color {
        viewModel.isPositive ? accentColor : .red
    }
}

#Preview("Positive Trend") {
    StockChart(
        startValue: 100,
        endValue: 142.50,
        selectedRange: .all,
        accentColor: .green
    )
    .padding()
}

#Preview("Negative Trend") {
    StockChart(
        startValue: 150,
        endValue: 120,
        selectedRange: .month,
        accentColor: .green
    )
    .padding()
}

#Preview("Dark Mode") {
    StockChart(
        startValue: 50,
        endValue: 85,
        selectedRange: .week,
        accentColor: .blue
    )
    .padding()
    .preferredColorScheme(.dark)
}
