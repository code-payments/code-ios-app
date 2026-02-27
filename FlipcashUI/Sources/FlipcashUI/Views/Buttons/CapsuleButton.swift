//
//  CapsuleButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct CapsuleButton: View {

    private let state: ButtonState
    private let image: Image
    private let title: String?
    private let action: VoidAction

    // MARK: - Init -

    public init(state: ButtonState, systemSymbol: SystemSymbol, title: String?, action: @escaping VoidAction) {
        self.init(
            state: state,
            image: Image.system(systemSymbol),
            title: title,
            action: action
        )
    }

    public init(state: ButtonState, asset: Asset, title: String?, action: @escaping VoidAction) {
        self.init(
            state: state,
            image: Image.asset(asset),
            title: title,
            action: action
        )
    }

    public init(state: ButtonState, image: Image, title: String?, binding: Binding<Bool>) {
        self.init(
            state: state,
            image: image,
            title: title
        ) {
            binding.wrappedValue.toggle()
        }
    }

    public init(state: ButtonState, image: Image, title: String?, action: @escaping VoidAction) {
        self.state  = state
        self.image  = image
        self.title  = title
        self.action = action
    }

    // MARK: - Body -

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 25, maxHeight: 25)

                if let title {
                    Text(title)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .font(.appTextMedium)
                        .minimumScaleFactor(0.8)
                }
            }
            .opacity(state == .normal ? 1 : 0)
            .overlay {
                switch state {
                case .normal:
                    EmptyView()

                case .loading:
                    LoadingView(color: .textMain)
                        .frame(maxWidth: 25, maxHeight: 25)

                case .success, .successText:
                    VStack {
                        Image.asset(.checkmark)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(Color.textSuccess)
                            .frame(maxWidth: 15, maxHeight: 15)
                    }
                    .frame(maxWidth: 25, maxHeight: 25)
                }
            }
            .animation(nil, value: state)
            .foregroundStyle(Color.textMain)
            .frame(height: 57)
            .padding(.horizontal, title == nil ? 16 : 20)
        }
        .buttonStyle(.liquidGlassCompatible)
    }
}

// MARK: - Previews -

struct CapsuleButton_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            HStack(spacing: 20) {
                Spacer()
                CapsuleButton(state: .normal, asset: .send,   title: "Send",   action: {})
                CapsuleButton(state: .normal, asset: .cancel, title: "Cancel", action: {})
                Spacer()
            }
        }
        .previewLayout(.fixed(width: 500, height: 400))
    }
}
