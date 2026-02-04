//
//  CurrencyInfoErrorView.swift
//  Code
//
//  Created by Claude on 2025-02-04.
//

import SwiftUI
import FlipcashUI

struct CurrencyInfoErrorView: View {
    let error: CurrencyInfoViewModel.Error
    let onRetry: () async -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(Color.textSecondary)

            Text(title)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)

            Text(subtitle)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            CodeButton(style: .filled, title: "Try Again") {
                Task {
                    await onRetry()
                }
            }
            .padding(20)
        }
    }

    private var title: String {
        switch error {
        case .mintNotFound:
            return "Currency Not Found"
        case .networkError:
            return "Connection Error"
        }
    }

    private var subtitle: String {
        switch error {
        case .mintNotFound:
            return "This currency could not be found. It may no longer exist."
        case .networkError:
            return "Please check your connection and try again."
        }
    }
}
