//
//  ImmutableField.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct ImmutableField: View {

    private var content: String
    private var state: State?
    private var leadingIcon: Image?

    public init(_ content: String, leadingIcon: Image? = nil, state: State? = nil) {
        self.content = content
        self.leadingIcon = leadingIcon
        self.state = state
    }

    public var body: some View {
        InputContainer {
            HStack(spacing: 2) {
                Text(content)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)

                if let state = state {
                    Spacer()
                    state.image
                        .renderingMode(.template)
                        .frame(minWidth: 26)
                        .foregroundStyle(state.color)
                }
            }
            .padding(15)
            // 29pt extra leading clears the 18×14 icon at 15pt inset (icon's
            // right edge = 33pt; content starts at 15 + 29 = 44pt → 11pt gap).
            // If the icon geometry changes, this offset must change in lockstep.
            .padding(.leading, leadingIcon != nil ? 29 : 0)
            .font(.appTextMedium)
            .foregroundStyle(.textMain)
            .overlay(alignment: .leading) {
                if let leadingIcon {
                    leadingIcon
                        .resizable()
                        .frame(width: 18, height: 14)
                        .padding(.leading, 15)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

// MARK: - State -

public extension ImmutableField {
    enum State: Equatable {
        
        case success(Image)
        case `default`(Image)
        
        var image: Image {
            switch self {
            case .success(let image):
                return image
            case .default(let image):
                return image
            }
        }
        
        var color: Color {
            switch self {
            case .success:
                return .textSuccess
            case .default:
                return .textSecondary
            }
        }
    }
}

// MARK: - Previews -

struct ImmutableField_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                ImmutableField("9xFTcyYWKmU3dXwayxaGCmHrCoWgUrSvqEiJu6i9YD9", state: .default(.system(.doc)))
                ImmutableField("849.99")
            }
            .padding(20)
        }
        .previewLayout(.fixed(width: 400, height: 300))
    }
}
