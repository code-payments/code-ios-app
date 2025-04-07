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
    private let image: Image?
    private let title: String
    private let action: VoidAction
    private let disabled: Bool
    
    // MARK: - Init -
    
    public init(style: Style, image: Image? = nil, title: String, disabled: Bool = false, action: @escaping VoidAction) {
        self.init(isLoading: false, style: style, image: image, title: title, disabled: disabled, action: action)
    }
    
    public init(isLoading: Bool, style: Style, image: Image? = nil, title: String, disabled: Bool = false, action: @escaping VoidAction) {
        self.init(state: isLoading ? .loading : .normal, style: style, image: image, title: title, disabled: disabled, action: action)
    }
    
    public init(state: ButtonState, style: Style, image: Image? = nil, title: String, disabled: Bool = false, action: @escaping VoidAction) {
        self.state = state
        self.style = style
        self.image = image
        self.title = title
        self.action = action
        self.disabled = disabled
    }
    
    // MARK: - Body -
    
    public var body: some View {
        Group {
            switch style {
            case .bordered, .filled, .filledMedium, .filledThin:
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
                        .foregroundColor(.textSuccess)
                    
                case .successText(let text):
                    HStack(spacing: 10) {
                        Image.asset(.checkmark)
                            .renderingMode(.template)
                            .foregroundColor(.textSuccess)
                        Text(text)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
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
        case .filled, .filledMedium, .filledThin, .subtle:
            return .textSecondary
        }
    }
    
    private func buttonHeight() -> CGFloat {
        switch style {
        case .filledThin:
            return Metrics.buttonHeightThin
        case .filledMedium:
            return 55
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
        case filledMedium
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
                
            case .filled, .filledMedium, .filledThin:
                if isDisabled {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .fill(Color.actionDisabled)
                } else {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .fill(Color.action)
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
                
            case .filled, .filledMedium, .filledThin:
                if isDisabled {
                    return .textActionDisabled
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
