//
//  SheetGeneric.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct SheetGeneric: View {
    
    public let asset: Asset
    public let title: String
    public let description: String
    public let actionName: String
    public let isPresented: Binding<Bool>?
    public let action: VoidAction
    
    public init(asset: Asset, title: String, description: String, actionName: String, isPresented: Binding<Bool>? = nil, action: @escaping VoidAction) {
        self.asset = asset
        self.title = title
        self.description = description
        self.actionName = actionName
        self.isPresented = isPresented
        self.action = action
    }
    
    public var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Image.asset(.bell)
            
            VStack(alignment: .center, spacing: 10) {
                Text(title)
                    .padding(.horizontal, 20)
                    .font(.appDisplaySmall)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.appTextSmall)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)
            
            CodeButton(style: .filled, title: actionName, action: action)
                .padding(.top, 10)
        }
        .padding(20)
        .foregroundColor(.textMain)
        .if(isPresented != nil) { $0
            .overlay {
                VStack(alignment: .trailing) {
                    HStack {
                        Spacer()
                        
                        Button {
                            isPresented?.wrappedValue = false
                        } label: {
                            Image.asset(.close)
                                .padding(20)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
    }
}
