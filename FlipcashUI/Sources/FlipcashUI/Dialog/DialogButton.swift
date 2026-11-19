//
//  DialogButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct DialogButton: View {
    
    private let state: ButtonState
    private let style: Style
    private let image: Image?
    private let title: String
    private let action: VoidAction
    private let disabled: Bool
    
    // MARK: - Init -
    
    public init(state: ButtonState = .normal, style: Style, image: Image? = nil, title: String, disabled: Bool = false, action: @escaping VoidAction) {
        self.state    = state
        self.style    = style
        self.image    = image
        self.title    = title
        self.action   = action
        self.disabled = disabled
    }
    
    // MARK: - Body -
    
    public var body: some View {
        Group {
            switch style {
            case .primary, .secondary, .destructive, .outline:
                button()
                    .buttonStyle(CustomStyle(style: style, isDisabled: isDisabled()))
                
            case .subtle:
                button()
                    .opacity(disabled ? 0.5 : 1.0)
                    .foregroundStyle(Color.textMain.opacity(0.6))
            }
        }
        .disabled(isDisabled())
    }
    
    @ViewBuilder private func button() -> some View {
        Button(action: action) {
            HStack {
                switch state {
                case .normal:
                    HStack(spacing: 10) {
                        if let image {
                            image
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 20, height: 20, alignment: .center)
                        }
                        Text(title)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }
                    
                case .loading:
                    LoadingView(color: loaderColor())
                    
                case .success:
                    Image.asset(.checkmark)
                        .renderingMode(.template)
                        .foregroundStyle(.textSuccess)
                    
                case .successText(let text):
                    HStack(spacing: 10) {
                        Image.asset(.checkmark)
                            .renderingMode(.template)
                            .foregroundStyle(.textSuccess)
                        Text(text)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.textMain)
                    }
                }
            }
            .font(.appTextMedium)
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight())
            .padding([.leading, .trailing], Metrics.buttonPadding)
        }
    }
    
    private func isDisabled() -> Bool {
        disabled || !state.isNormal
    }
    
    private func loaderColor() -> Color {
        .textSecondary
    }
    
    private func buttonHeight() -> CGFloat {
        Metrics.buttonHeight
    }
}

// MARK: - Style -

extension DialogButton {
    public enum Style {
        case primary
        case secondary
        case destructive
        case subtle
        case outline
    }
}

// MARK: - CustomStyle -

private extension DialogButton {
    struct CustomStyle: ButtonStyle {
        
        let style: DialogButton.Style
        let isDisabled: Bool
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(background(style: style))
                .foregroundStyle(textColor())
                .contentShape(Capsule())
                .buttonPress(isPressed: configuration.isPressed)
        }
        
        @ViewBuilder private func background(style: DialogButton.Style) -> some View {
            switch style {
            case .primary, .secondary, .destructive:
                if isDisabled {
                    Capsule()
                        .fill(Color.actionDisabled)
                } else {
                    Capsule()
                        .fill(Color.action)
                }
                
            case .outline:
                if isDisabled {
                    Capsule()
                        .stroke(Color.backgroundRow.opacity(0.6), lineWidth: Metrics.buttonLineWidth)
                } else {
                    Capsule()
                        .stroke(Color.textMain.opacity(0.6), lineWidth: Metrics.buttonLineWidth)
                }
                
            case .subtle:
                fatalError()
            }
        }
        
        private func textColor() -> Color {
            switch style {
            case .primary, .secondary:
                if isDisabled {
                    return .textActionDisabled
                } else {
                    return .textAction
                }
                
            case .destructive:
                if isDisabled {
                    return .textActionDisabled
                } else {
                    return .bannerError
                }
                
            case .outline:
                if isDisabled {
                    return .backgroundRow.opacity(0.6)
                } else {
                    return .textMain
                }
                
            case .subtle:
                fatalError()
            }
        }
    }
}
