//
//  EmptyStateMessage.swift
//  FlipcashUI
//

import SwiftUI

/// The centered title and explanation a settings-style list shows when it has nothing to list, as
/// on Blocked Users and Trusted Websites.
public struct EmptyStateMessage: View {

    private let title: String
    private let message: String?

    // MARK: - Init -

    public init(_ title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }

    // MARK: - Body -

    public var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
            if let message {
                Text(message)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
    }
}
