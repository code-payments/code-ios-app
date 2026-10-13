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
    public let checkbox: DialogCheckbox?
    public let dismiss: () -> Void
    public let actions: [DialogAction]

    @State private var isChecked = false
    
    // MARK: - Init -
    
    public init(style: Style, title: String?, subtitle: String?, options: Options = [], checkbox: DialogCheckbox? = nil, dismiss: @escaping () -> Void, actions: [DialogAction]) {
        self.style    = style
        self.title    = title
        self.subtitle = subtitle
        self.options  = options
        self.checkbox = checkbox
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

            if let checkbox {
                checkboxRow(checkbox)
            }
            
            VStack(spacing: 0) {
                ForEach(actions, id: \.title) { action in
                    DialogButton(
                        style: action.kind.buttonStyle,
                        title: action.title
                    ) {
                        if options.contains(.priorityAction) {
                            action.perform(isChecked: isChecked)
                            dismiss()
                        } else {
                            dismiss()
                            action.perform(isChecked: isChecked)
                        }
                    }
                    .padding(.top, action.kind.topPadding)
                }
            }
        }
        .padding([.leading, .trailing, .top], 20)
        .padding(.bottom, actions.last?.kind.bottomPadding ?? 0)
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .background(style.backgroundColor)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(title ?? "Dialog")
    }

    private func checkboxRow(_ checkbox: DialogCheckbox) -> some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                Text(checkbox.label)
                    .font(.default(size: 14, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textMain)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
        .accessibilityIdentifier("dialog-checkbox")
    }
}

extension Dialog {
    public enum Style: Equatable {
        case standard
        case success
        case destructive
        
        public var backgroundColor: Color {
            switch self {
            case .standard:    return .bannerInfo
            case .success:     return .bannerSuccess
            case .destructive: return .bannerError
            }
        }
    }
}
