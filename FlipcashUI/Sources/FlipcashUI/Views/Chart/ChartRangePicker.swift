import SwiftUI

/// Segmented picker for selecting chart time ranges
public struct ChartRangePicker: View {
    @Binding var selectedRange: ChartRange
    let accentColor: Color
    
    @Namespace private var animation
    @Environment(\.colorScheme) private var colorScheme

    public init(selectedRange: Binding<ChartRange>, accentColor: Color) {
        self._selectedRange = selectedRange
        self.accentColor = accentColor
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(ChartRange.allCases) { range in
                Button {
                    withAnimation(.snappy(duration: 0.15)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.title)
                        .font(.appTextMedium)
                        .fontWeight(.semibold)
                        .foregroundStyle(selectedRange == range ? Color.textMain : unselectedInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selectedRange == range {
                                Capsule()
                                    .fill(accentColor)
                                    .matchedGeometryEffect(id: "selection", in: animation)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The system secondary in dark; in light, where it reads at 3.44:1 on the page, `textSecondary`.
    private var unselectedInk: Color {
        colorScheme == .dark ? Color.secondary : Color.textSecondary
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var range: ChartRange = .all
        
        var body: some View {
            ChartRangePicker(selectedRange: $range, accentColor: .mint)
        }
    }
    
    return PreviewWrapper()
        .padding()
}
