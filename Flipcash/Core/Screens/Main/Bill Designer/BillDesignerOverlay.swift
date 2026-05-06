//
//  BillDesignerOverlay.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct BillDesignerOverlay: View {

    @Environment(Session.self) private var session

    @Binding var colors: [Color]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Button(action: copyHexCodes) {
                    ButtonIcon(systemName: "doc.on.doc")
                }
                .liquidGlassButtonStyle(shape: .circle)
                .accessibilityLabel("Copy bill colors")

                Button {
                    session.isShowingBillDesigner = false
                } label: {
                    ButtonIcon(systemName: "xmark")
                }
                .liquidGlassButtonStyle(shape: .circle)
                .accessibilityLabel("Close bill designer")
            }
            .padding(.horizontal, 16)

            BillDesigner(backgroundColors: $colors)
                .frame(maxWidth: .infinity)
        }
    }

    private func copyHexCodes() {
        let hexColors = colors.map { $0.hexString }
        UIPasteboard.general.string = hexColors.joined(separator: ", ")
    }
}

private struct ButtonIcon: View {
    let systemName: String

    var body: some View {
        if #available(iOS 26, *) {
            Image(systemName: systemName)
                .foregroundStyle(Color.textMain)
                .font(.appTextLarge)
                .frame(width: 32, height: 32)
        } else {
            Image(systemName: systemName)
                .foregroundStyle(Color.textMain)
                .font(.appTextLarge)
                .frame(width: 44, height: 44)
        }
    }
}
