//
//  Badge.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Badge: View {
    
    private let decoration: Decoration
    private let text: String
    
    // MARK: - Init -
    
    public init(decoration: Decoration, text: String) {
        self.decoration = decoration
        self.text = text
    }
    
    // MARK: - Body -
    
    public var body: some View {
        HStack(spacing: spacing(for: decoration)) {
            switch decoration {
            case .none:
                EmptyView()
            case .bubble(let color):
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                
            case .circle(let color):
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                
            case .checkmark:
                Image.asset(.checkmark)
                    .renderingMode(.template)
                    .foregroundColor(.textSuccess)
            }
            Text(text)
                .foregroundColor(textColor(for: decoration))
                .font(.appTextSmall)
        }
        .padding([.top, .bottom], verticalPadding(for: decoration))
        .padding([.leading], leadingPadding(for: decoration))
        .padding([.trailing], trailingPadding(for: decoration))
        .background(background(for: decoration))
    }
    
    @ViewBuilder private func background(for decoration: Decoration) -> some View {
        switch decoration {
        case .bubble:
            RoundedRectangle(cornerRadius: 99)
                .fill(Color.white.opacity(0.1))
        case .none, .circle, .checkmark:
            EmptyView()
        }
    }
    
    private func textColor(for decoration: Decoration) -> Color {
        switch decoration {
        case .none:      return .textSecondary
        case .bubble:    return .textMain
        case .circle:    return .textSecondary
        case .checkmark: return .textMain
        }
    }
    
    private func spacing(for decoration: Decoration) -> CGFloat {
        switch decoration {
        case .none:      return 8
        case .bubble:    return 8
        case .circle:    return 8
        case .checkmark: return 6
        }
    }
    
    private func leadingPadding(for decoration: Decoration) -> CGFloat {
        switch decoration {
        case .none:      return 0
        case .bubble:    return 12
        case .circle:    return 0
        case .checkmark: return 0
        }
    }
    
    private func trailingPadding(for decoration: Decoration) -> CGFloat {
        switch decoration {
        case .none:      return 0
        case .bubble:    return 12
        case .circle:    return 0
        case .checkmark: return 0
        }
    }
    
    private func verticalPadding(for decoration: Decoration) -> CGFloat {
        switch decoration {
        case .none:      return 0
        case .bubble:    return 6
        case .circle:    return 0
        case .checkmark: return 0
        }
    }
}

// MARK: - Decoration -

extension Badge {
    public enum Decoration {
        case none
        case bubble(Color)
        case circle(Color)
        case checkmark
    }
}

// MARK: - Previews -

struct Badge_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                Badge(decoration: .bubble(.textSuccess), text: "Invited")
                Badge(decoration: .checkmark,         text: "On Code")
            }
        }
    }
}
