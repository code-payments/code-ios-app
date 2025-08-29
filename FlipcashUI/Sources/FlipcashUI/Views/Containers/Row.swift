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

public struct NavigationRow<Content, Path>: View where Content: View {
    
    @Binding var path: [Path]
    
    public var insets: EdgeInsets
    public var disabled: Bool
    public var accessory: RowAccessory?
    public var pathItem: Path
    public var content: () -> Content
    
    // MARK: - Init -
    
    public init(path: Binding<[Path]>, insets: EdgeInsets, disabled: Bool = false, accessory: RowAccessory? = nil, pathItem: Path, @ViewBuilder content: @escaping () -> Content) {
        self._path     = path
        self.insets    = insets
        self.disabled  = disabled
        self.accessory = accessory
        self.pathItem  = pathItem
        self.content   = content
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                path.append(pathItem)
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
