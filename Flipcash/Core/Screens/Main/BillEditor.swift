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

    public let fiat: Quarks
    public let data: Data

    @State private var backgroundColors: [Color] = [Color(hue: 0.6, saturation: 0.7, brightness: 0.9)]

    // MARK: - Init -

    public init(fiat: Quarks, data: Data) {
        self.fiat = fiat
        self.data = data
    }

    // MARK: - Body -

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Bill View (takes available space)
                BillView(
                    fiat: fiat,
                    data: data,
                    canvasSize: geometry.size,
                    backgroundColors: backgroundColors
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Color Editor Control
                ColorEditorControl(colors: $backgroundColors)
            }
        }
    }
}

#Preview {
    BillEditor(fiat: 10_00, data: .placeholder35)
}

