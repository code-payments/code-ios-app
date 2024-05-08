//
//  CodeButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct CodeButton: View {
    
    private let state: ButtonState
    private let style: Style
    private let title: String
    private let action: VoidAction
    private let disabled: Bool
    
    // MARK: - Init -
    
    public init(style: Style, title: String, disabled: Bool = false, action: @escaping VoidAction) {
        self.init(isLoading: false, style: style, title: title, disabled: disabled, action: action)
    }
    
    public init(isLoading: Bool, style: Style, title: String, disabled: Bool = false, action: @escaping VoidAction) {
        self.init(state: isLoading ? .loading : .normal, style: style, title: title, disabled: disabled, action: action)
    }
    
    public init(state: ButtonState, style: Style, title: String, disabled: Bool = false, action: @escaping VoidAction) {
        self.state = state
        self.style = style
        self.title = title
        self.action = action
        self.disabled = disabled
    }
    
    // MARK: - Body -
    
    public var body: some View {
        Group {
            switch style {
            case .bordered, .filled, .filledThin:
                button()
                    .buttonStyle(CustomStyle(style: style, isDisabled: isDisabled()))
                
            case .subtle:
                button()
                    .opacity(disabled ? 0.5 : 1.0)
                    .foregroundColor(.textSecondary)
            }
        }
        .disabled(isDisabled())
    }
    
    @ViewBuilder private func button() -> some View {
        Button(action: action) {
            HStack {
                switch state {
                case .normal:
                    Text(title)
                    
                case .loading:
                    LoadingView(color: loaderColor())
                    
                case .success:
                    Image.asset(.checkmark)
                        .renderingMode(.template)
                        .foregroundColor(.textSuccess)
                    
                case .successText(let text):
                    HStack(spacing: 10) {
                        Image.asset(.checkmark)
                            .renderingMode(.template)
                            .foregroundColor(.textSuccess)
                        Text(text)
                            .foregroundColor(.textMain)
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
        switch style {
        case .bordered:
            return .textMain
        case .filled, .filledThin, .subtle:
            return .textSecondary
        }
    }
    
    private func buttonHeight() -> CGFloat {
        switch style {
        case .filledThin:
            return Metrics.buttonHeightThin
        case .bordered, .filled, .subtle:
            return Metrics.buttonHeight
        }
    }
}

// MARK: - Style -

extension CodeButton {
    public enum Style {
        case bordered
        case filled
        case filledThin
        case subtle
    }
}

// MARK: - CustomStyle -

private extension CodeButton {
    struct CustomStyle: ButtonStyle {
        
        let style: CodeButton.Style
        let isDisabled: Bool
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(background(style: style))
                .foregroundColor(textColor())
                .overlay(configuration.isPressed ? Color.black.opacity(0.3) : Color.black.opacity(0))
        }
        
        @ViewBuilder private func background(style: CodeButton.Style) -> some View {
            switch style {
            case .bordered:
                if isDisabled {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .stroke(Color.backgroundRow, lineWidth: Metrics.buttonLineWidth)
                } else {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .stroke(Color.textMain, lineWidth: Metrics.buttonLineWidth)
                }
                
            case .filled, .filledThin:
                if isDisabled {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .fill(Color(r: 27, g: 25, b: 41))
                } else {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .fill(Color.textMain)
                }
                
            case .subtle:
                fatalError()
            }
        }
        
        private func textColor() -> Color {
            switch style {
            case .bordered:
                if isDisabled {
                    return .backgroundRow
                } else {
                    return .textMain
                }
                
            case .filled, .filledThin:
                if isDisabled {
                    return Color(r: 48, g: 45, b: 63)
                } else {
                    return .textAction
                }
                
            case .subtle:
                fatalError()
            }
        }
    }
}

// MARK: - Previews -

struct CodeButton_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                Spacer()
                CodeButton(style: .filled, title: "Next", action: {})
                CodeButton(style: .filled, title: "Prev", action: {})
                CodeButton(isLoading: true, style: .filled, title: "Prev", action: {})
                CodeButton(style: .subtle, title: "Log In", action: {})
                CodeButton(style: .filled, title: "Create Account", action: {})
                Spacer()
            }
            .padding(20.0)
        }
    }
}

#endif
