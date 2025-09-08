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
            case .bordered, .filled, .filledApplePay, .filledDestructive, .filledMedium, .filledThin, .filledSecondary, .filledMediumSecondary:
                button()
                    .buttonStyle(CustomStyle(style: style, isDisabled: isDisabled()))
                
            case .subtle:
                button()
                    .opacity(disabled ? 0.5 : 1.0)
                    .foregroundColor(Color.textMain.opacity(0.6))
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
                        
                        titleView()
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
    
    @ViewBuilder private func titleView() -> some View {
        switch style {
        case .filledApplePay:
            HStack(spacing: 1) {
                Text("\(title) With ")
                HStack(spacing: 1) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 14, weight: .semibold))
                        .offset(y: -1)
                    Text("Pay")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            
        case .filled, .bordered, .filledDestructive, .filledMedium, .filledThin, .subtle, .filledSecondary, .filledMediumSecondary:
            Text(title)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
    }
    
    private func isDisabled() -> Bool {
        disabled || !state.isNormal
    }
    
    private func loaderColor() -> Color {
        switch style {
        case .bordered:
            return .textMain
        case .filled, .filledApplePay, .filledDestructive, .filledMedium, .filledThin, .subtle, .filledSecondary, .filledMediumSecondary:
            return .textSecondary
        }
    }
    
    private func buttonHeight() -> CGFloat {
        switch style {
        case .filledThin:
            return Metrics.buttonHeightThin
        case .filledMedium, .filledMediumSecondary:
            return 55
        case .bordered, .filled, .filledApplePay, .filledDestructive, .subtle, .filledSecondary:
            return Metrics.buttonHeight
        }
    }
}

// MARK: - Style -

extension CodeButton {
    public enum Style {
        case bordered
        case filled
        case filledApplePay
        case filledSecondary
        case filledDestructive
        case filledMedium
        case filledMediumSecondary
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
                
            case .filled, .filledApplePay, .filledDestructive, .filledMedium, .filledThin:
                if isDisabled {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .fill(Color.actionDisabled)
                } else {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .fill(Color.action)
                }
                
            case .filledSecondary, .filledMediumSecondary:
                if isDisabled {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .fill(Color.actionDisabled)
                } else {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .fill(Color(r: 55, g: 71, b: 62))
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
                
            case .filledDestructive:
                if isDisabled {
                    return .textActionDisabled
                } else {
                    return .bannerError
                }
                
            case .filled, .filledApplePay, .filledMedium, .filledThin:
                if isDisabled {
                    return .textActionDisabled
                } else {
                    return .textAction
                }
                
            case .filledSecondary, .filledMediumSecondary:
                if isDisabled {
                    return Color(r: 19, g: 30, b: 24)
                } else {
                    return .textMain
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
