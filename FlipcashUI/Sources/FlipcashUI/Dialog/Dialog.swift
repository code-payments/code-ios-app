//
//  Dialog.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-05-06.
//

import SwiftUI

public struct Dialog: View {
    
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int

        public static let priorityAction = Options(rawValue: 1 << 0)
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    public let style: Style
    public let title: String?
    public let subtitle: String?
    public let options: Options
    public let dismiss: () -> Void
    public let actions: [DialogAction]
    
    // MARK: - Init -
    
    public init(style: Style, title: String?, subtitle: String?, options: Options = [], dismiss: @escaping () -> Void, actions: [DialogAction]) {
        self.style    = style
        self.title    = title
        self.subtitle = subtitle
        self.options  = options
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
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let subtitle {
                    Text(subtitle)
                        .font(.appTextSmall)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 2)
            .foregroundStyle(Color.textMain)
            
            VStack(spacing: 0) {
                ForEach(actions, id: \.title) { action in
                    DialogButton(
                        style: action.kind.buttonStyle,
                        title: action.title
                    ) {
                        if options.contains(.priorityAction) {
                            action.action()
                            dismiss()
                        } else {
                            dismiss()
                            action.action()
                        }
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
