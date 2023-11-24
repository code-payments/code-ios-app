//
//  Row.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Row<Content>: View where Content: View {
    
    public var insets: EdgeInsets
    public var disabled: Bool
    public var accessory: RowAccessory?
    public var content: () -> Content
    public var action: VoidAction
    
    // MARK: - Init -
    
    public init(insets: EdgeInsets, disabled: Bool = false, accessory: RowAccessory? = nil, @ViewBuilder content: @escaping () -> Content, action: VoidAction? = nil) {
        self.insets = insets
        self.disabled = disabled
        self.accessory = accessory
        self.content = content
        self.action = action ?? {}
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    content()
                    if let accessory {
                        switch accessory {
                        case .chevron:
                            Spacer()
                            Image.system(.chevronRight)
                                .renderingMode(.template)
                        case .loader(let color):
                            Spacer()
                            LoadingView(color: color)
                        }
                    }
                }
                .padding(.leading, insets.leading)
                .padding(.bottom, insets.bottom)
                .padding(.trailing, insets.trailing)
                .padding(.top, insets.top)
            }
            .disabled(disabled)
            .vSeparator(color: .rowSeparator, position: .bottom)
        }
        .foregroundColor(disabled ? .textSecondary : .textMain)
    }
}

public struct NavigationRow<Content, Destination>: View where Content: View, Destination: View {
    
    public var insets: EdgeInsets
    public var disabled: Bool
    public var accessory: RowAccessory?
    public var destination: () -> Destination
    public var content: () -> Content
    public var action: VoidAction
    
    // MARK: - Init -
    
    public init(insets: EdgeInsets, disabled: Bool = false, accessory: RowAccessory? = nil, @ViewBuilder destination: @escaping () -> Destination, @ViewBuilder content: @escaping () -> Content, action: VoidAction? = nil) {
        self.insets = insets
        self.disabled = disabled
        self.accessory = accessory
        self.destination = destination
        self.content = content
        self.action = action ?? {}
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: action, label: {
                NavigationLink {
                    destination()
                } label: {
                    HStack(spacing: 12) {
                        content()
                        if let accessory {
                            switch accessory {
                            case .chevron:
                                Spacer()
                                Image.system(.chevronRight)
                                    .renderingMode(.template)
                            case .loader(let color):
                                Spacer()
                                LoadingView(color: color)
                            }
                        }
                    }
                    .padding(.leading, insets.leading)
                    .padding(.bottom, insets.bottom)
                    .padding(.trailing, insets.trailing)
                    .padding(.top, insets.top)
                }
            })
            .disabled(disabled)
            .vSeparator(color: .rowSeparator, position: .bottom)
        }
        .foregroundColor(disabled ? .textSecondary : .textMain)
    }
}

public enum RowAccessory {
    case chevron
    case loader(Color)
}

extension EdgeInsets {
    public static func equal(_ value: CGFloat) -> EdgeInsets {
        EdgeInsets(top: value, leading: value, bottom: value, trailing: value)
    }
}

// MARK: - Previews -

struct Row_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Row(insets: .equal(10)) {
                    Text("Title")
                    Spacer()
                    Text("Subtitle")
                }
                Row(insets: .equal(20)) {
                    Text("Title")
                }
                Row(insets: .equal(30)) {
                    Text("Title")
                }
                Row(insets: .equal(40)) {
                    Text("Title")
                }
                Row(insets: .equal(50)) {
                    Text("Title")
                }
                Row(insets: .equal(60)) {
                    Text("Title")
                }
                Spacer()
            }
            .foregroundColor(.textMain)
        }
        .previewLayout(.fixed(width: 320, height: 550))
    }
}
