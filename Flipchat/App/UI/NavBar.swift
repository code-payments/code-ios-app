//
//  NavBar.swift
//  Flipchat
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeUI
import FlipchatServices

public struct NavBar<Leading, Trailing>: View where Leading: View, Trailing: View {
    
    public let isLoading: Bool
    public let alignment: VerticalAlignment
    public let title: String
    public let titleAction: () -> Void
    public let leading: () -> Leading
    public let trailing: () -> Trailing
    
    public init(
        isLoading: Bool = false,
        alignment: VerticalAlignment = .center,
        title: String,
        titleAction: @escaping () -> Void = {},
        @ViewBuilder leading: @escaping () -> Leading = { NavBarEmptyItem() },
        @ViewBuilder trailing: @escaping () -> Trailing = { NavBarEmptyItem() }
    ) {
        self.isLoading = isLoading
        self.alignment = alignment
        self.title = title
        self.titleAction = titleAction
        self.leading = leading
        self.trailing = trailing
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: alignment) {
                leading()
                    .frame(width: 44, height: 44)
                
                Spacer()
                
                if isLoading {
                    HStack {
                        LoadingView(color: .textSecondary)
                        Text("Updating...")
                            .foregroundColor(.textMain)
                            .font(.appTextMedium)
                    }
                } else {
                    Text(title)
                        .foregroundColor(.textMain)
                        .font(.appTitle)
                        .onTapGesture {
                            titleAction()
                        }
                }
                    
                Spacer()
                
                trailing()
                    .frame(width: 44, height: 44)
            }
            .padding([.leading, .trailing], 10)
        }
        .frame(height: 44)
    }
}

public struct NavBarEmptyItem: View {
    
    public init() {}
    
    public var body: some View {
        Spacer()
            .frame(width: 60, height: 60, alignment: .center)
    }
}

public struct NavBarCloseItem: View {
    
    @Binding public var isPresented: Bool
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image.asset(.close)
                .padding(20)
        }
    }
}

// MARK: - Previews -

#Preview {
    Background(color: .backgroundMain) {
        VStack {
            ModalHeaderBar(title: "Give Kin", isPresented: .constant(true))
            Spacer()
        }
    }
}
