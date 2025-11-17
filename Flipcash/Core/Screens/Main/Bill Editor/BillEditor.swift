//
//  BillEditor.swift
//  Code
//
//  Created by Dima Bart on 2025-11-07.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

public struct BillEditor: View {

    @Binding public var backgroundColors: [Color]

    // MARK: - Init -

    public init(backgroundColors: Binding<[Color]>) {
        self._backgroundColors = backgroundColors
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                BillView(
                    fiat: try! Quarks(fiatDecimal: 10, currencyCode: .usd, decimals: 6),
                    data: .placeholder35,
                    canvasSize: CGSize(
                        width: geometry.size.width,
                        height: geometry.size.height * 0.65  // Use top half for bill
                    ),
                    backgroundColors: backgroundColors
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

                ColorEditorControl(colors: $backgroundColors)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 20)
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .background(alignment: .bottom) {
            LinearGradient(
                gradient: Gradient(
                    colors: [
                        .init(white: 0),
                        .clear,
                    ]
                ),
                startPoint: .bottom,
                endPoint: .top
            )
            .edgesIgnoringSafeArea(.bottom)
        }
    }
}

#Preview {
    BillEditor(backgroundColors: .constant([Color(hue: 0.6, saturation: 0.7, brightness: 0.9)]))
}

