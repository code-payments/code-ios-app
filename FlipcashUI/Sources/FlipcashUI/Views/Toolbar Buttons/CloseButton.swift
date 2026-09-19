import SwiftUI

/// The app's dismiss button: an `xmark`, bare or on a Liquid Glass platter.
public struct CloseButton: View {

    /// How the button is drawn.
    public enum Style {
        /// A bare glyph taking its colour from the caller. What a navigation bar wants.
        case plain
        /// The glyph on a circular Liquid Glass platter, for a close that sits over content
        /// rather than in a bar.
        case glass
    }

    private let style: Style
    private let action: VoidAction

    public init(style: Style = .plain, binding: Binding<Bool>) {
        self.style = style
        self.action = { binding.wrappedValue = false }
    }

    public init(style: Style = .plain, action: @escaping VoidAction) {
        self.style = style
        self.action = action
    }

    @ViewBuilder
    public var body: some View {
        switch style {
        case .plain:
            Button(action: action) {
                glyph
                    .padding(5)
            }
            .accessibilityLabel("Close")

        case .glass:
            Button(action: action) {
                glyph
                    .foregroundStyle(Color.textMain)
                    .frame(width: platterDiameter, height: platterDiameter)
            }
            .liquidGlassButtonStyle(shape: .circle)
            .accessibilityLabel("Close")
        }
    }

    private var glyph: some View {
        Image(systemName: "xmark")
            .fontWeight(.semibold)
    }

    /// iOS 26's `.glass` button style insets its own label, so the frame it wraps is smaller than
    /// the one the material fallback draws its circle directly around.
    private var platterDiameter: CGFloat {
        if #available(iOS 26, *) { 32 } else { 44 }
    }
}

#Preview {
    NavigationStack {
        Text("Some View")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton {}
                }
                ToolbarItem(placement: .topBarLeading) {
                    CloseButton(style: .glass) {}
                }
            }
    }
}
