//
//  CurrencyInfoFooter.swift
//  Code
//
//  Created by Dima Bart on 2025-10-28.
//

import SwiftUI
import FlipcashUI

struct CurrencyInfoFooter<Content>: View where Content: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                content
            }
            .padding(20)
            .background {
                LinearGradient(
                    gradient: Gradient(colors: [Color.backgroundMain, Color.backgroundMain, .clear]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea()
            }
        }
    }
}
