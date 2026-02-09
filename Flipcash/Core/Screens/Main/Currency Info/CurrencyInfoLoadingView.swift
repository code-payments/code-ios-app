//
//  CurrencyInfoLoadingView.swift
//  Code
//
//  Created by Claude on 2025-02-04.
//

import SwiftUI
import FlipcashUI

struct CurrencyInfoLoadingView: View {
    var body: some View {
        Background(color: .backgroundMain) {
            Spacer()
            LoadingView(color: .textMain)
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }
}
