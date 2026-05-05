//
//  BillDesigner.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

public struct BillDesigner: View {

    @Binding public var backgroundColors: [Color]

    public init(backgroundColors: Binding<[Color]>) {
        self._backgroundColors = backgroundColors
    }

    /// The view is intentionally transparent above the bottom gradient so the
    /// underlying camera viewport on `ScanScreen` remains visible behind the
    /// bill preview. Anything that should be hidden while the designer is up
    /// (e.g. `ScanScreen`'s top/bottom bars) needs to be faded out by the
    /// caller — don't add a background here.
    public var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                BillView(
                    fiat: FiatAmount(value: 10, currency: .usd),
                    data: .placeholder35,
                    canvasSize: CGSize(
                        width: geometry.size.width,
                        height: geometry.size.height
                    ),
                    backgroundColors: backgroundColors
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 20)

            ColorEditorControl(colors: $backgroundColors)
                .padding(.bottom, 20)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ignoresSafeArea(.container, edges: .bottom)
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
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

#Preview {
    BillDesigner(
        backgroundColors: .constant(ColorEditorControl.deriveColors(fromHue: 0.6))
    )
}
