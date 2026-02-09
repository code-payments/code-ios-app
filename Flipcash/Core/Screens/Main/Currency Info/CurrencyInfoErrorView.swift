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
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("IconExclamationCircle")
                .resizable()
                .frame(width: 100, height: 100)
                .padding(24)

            // Status Text
            VStack(spacing: 12) {
                Text(title)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)

                Text(subtitle)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            
            Spacer()

            CodeButton(style: .filled, title: "OK") {
                onAction()
            }
            .padding(20)
        }
    }

    private var title: String {
        switch error {
        case .mintNotFound:
            return "Currency Not Found"
        case .networkError:
            return "Something Went Wrong"
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
