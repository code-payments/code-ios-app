//
//  LargeButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct LargeButton: View {

    private let title: String
    private let image: Image
    private let action: VoidAction

    public init(title: String, image: Image, action: @escaping VoidAction) {
        self.title  = title
        self.image  = image
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                Text(title)
                    .font(.appTextSmall)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .bottom)
        }
        .foregroundStyle(.textMain)
    }
}

// MARK: - Previews -

#Preview {
    Background(color: .backgroundMain) {
        HStack(alignment: .bottom) {
            LargeButton(title: "History", image: .asset(.history)) {}
            LargeButton(title: "Invites", image: .asset(.invites)) {}
        }
    }
}
