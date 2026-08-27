//
//  ButtonStateLabel.swift
//  FlipcashUI
//

import SwiftUI

/// The label for a button whose action reports progress: the title, a spinner
/// while the action runs, then the checkmark the app confirms a completed
/// action with.
///
/// `ButtonStyle` can't see the action's state, so a `Button` wearing one of the
/// modern styles (`.filled` and friends) renders this in place of a plain title.
/// `CodeButton` draws the same states itself and needs none of this.
public struct ButtonStateLabel: View {

    private let title: String
    private let state: ButtonState

    // MARK: - Init -

    public init(_ title: String, state: ButtonState) {
        self.title = title
        self.state = state
    }

    // MARK: - Body -

    public var body: some View {
        switch state {
        case .normal:
            Text(title)

        case .loading:
            ProgressView()
                .progressViewStyle(.circular)

        case .success:
            checkmark

        case .successText(let text):
            HStack(spacing: 10) {
                checkmark
                Text(text)
                    .foregroundStyle(Color.textMain)
            }
        }
    }

    /// Colored explicitly: callers disable the button while the action is in
    /// flight, so the checkmark would otherwise take the style's dimmed
    /// disabled color.
    private var checkmark: some View {
        Image.asset(.checkmark)
            .renderingMode(.template)
            .foregroundStyle(Color.textMain)
    }
}

// MARK: - Previews -

#Preview {
    Background(color: .backgroundMain) {
        VStack(spacing: 20) {
            Button {} label: {
                ButtonStateLabel("Next", state: .normal)
            }
            Button {} label: {
                ButtonStateLabel("Next", state: .loading)
            }
            .disabled(true)
            Button {} label: {
                ButtonStateLabel("Next", state: .success)
            }
            .disabled(true)
        }
        .buttonStyle(.filled)
        .padding(20)
    }
}
