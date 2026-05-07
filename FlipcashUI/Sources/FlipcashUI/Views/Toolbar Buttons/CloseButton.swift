import SwiftUI

public struct CloseButton: View {

    private let action: VoidAction

    public init(binding: Binding<Bool>) {
        self.action = { binding.wrappedValue = false }
    }

    public init(action: @escaping VoidAction) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .fontWeight(.semibold)
                .padding(5)
        }
        .accessibilityLabel("Close")
    }
}

#Preview {
    NavigationStack {
        Text("Some View")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton {}
                }
            }
    }
}
