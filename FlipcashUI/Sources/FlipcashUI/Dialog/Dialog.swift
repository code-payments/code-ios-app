//
//  Dialog.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-05-06.
//

import SwiftUI

public struct Dialog: View {
    
    public let style: Style
    public let title: String?
    public let subtitle: String?
    public let dismiss: () -> Void
    public let actions: [DialogAction]
    
    // MARK: - Init -
    
    public init(style: Style, title: String?, subtitle: String?, dismiss: @escaping () -> Void, actions: [DialogAction]) {
        self.style    = style
        self.title    = title
        self.subtitle = subtitle
        self.dismiss  = dismiss
        self.actions  = actions
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                if let title {
                    Text(title)
                        .font(.appTextLarge)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let subtitle {
                    Text(subtitle)
                        .font(.appTextSmall)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 2)
            .foregroundStyle(Color.textMain)
            
            VStack(spacing: 0) {
                ForEach(actions, id: \.title) { action in
                    CodeButton(
                        style: action.kind.buttonStyle,
                        title: action.title
                    ) {
                        action.action()
                        dismiss()
                    }
                    .padding(.top, action.kind.topPadding)
                }
            }
        }
        .padding([.leading, .trailing, .top], 20)
        .padding(.bottom, actions.last?.kind.bottomPadding ?? 0)
        .frame(maxWidth: .infinity)
        .foregroundColor(.white)
        .background(style.backgroundColor)
    }
}

extension Dialog {
    public enum Style {
        case standard
        case success
        case destructive
        
        var backgroundColor: Color {
            switch self {
            case .standard:    return .bannerInfo
            case .success:     return .bannerSuccess
            case .destructive: return .bannerError
            }
        }
    }
}
