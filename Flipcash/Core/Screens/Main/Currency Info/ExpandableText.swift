//
//  ExpandableText.swift
//  Code
//
//  Created by Dima Bart on 2025-10-28.
//

import SwiftUI
import FlipcashUI

struct ExpandableText: View {
    @State private var isExpanded: Bool

    private let text: String
    private let color: Color
    private let backgroundColor: Color
    private let drawer: (() -> AnyView)?

    init(
        _ text: String,
        color: Color = Color(r: 155, g: 163, b: 158),
        backgroundColor: Color = .backgroundMain,
        expanded: Bool = false,
        drawer: (() -> AnyView)? = nil
    ) {
        self.text            = text
        self.color           = color
        self.backgroundColor = backgroundColor
        self.drawer          = drawer
        self._isExpanded     = State(initialValue: expanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: isExpanded ? nil : 40, alignment: .topLeading)
                .overlay {
                    if !isExpanded {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        backgroundColor,
                                        backgroundColor.opacity(0),
                                    ]),
                                    startPoint: .bottom,
                                    endPoint: UnitPoint(x: 0.5, y: 0.0)
                                )
                            )
                    }
                }

            if isExpanded, let drawer = drawer {
                drawer()
                    .padding(.top, 20)
                    .padding(.bottom, 15)
            }

            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Show \(isExpanded ? "less" : "more")")
                        .frame(width: 78, alignment: .leading)

                    Image(systemName: "chevron.up")
                        .rotationEffect(isExpanded ? .degrees(0) : .degrees(180))

                    Spacer()
                }
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .background(backgroundColor)
            }
        }
        .clipped()
    }
}
