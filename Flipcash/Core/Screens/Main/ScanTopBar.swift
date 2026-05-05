//
//  ScanTopBar.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct ScanTopBar: View {
    let onSettings: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Image.asset(.flipcashBrand)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 28)

            Spacer()

            Button(action: onSettings) {
                if #available(iOS 26, *) {
                    Image.asset(.hamburger)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.textMain)
                        .frame(width: 32, height: 32)
                } else {
                    Image.asset(.hamburger)
                        .foregroundStyle(Color.textMain)
                        .frame(width: 44, height: 44)
                }
            }
            .liquidGlassButtonStyle(shape: .circle)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
    }
}
