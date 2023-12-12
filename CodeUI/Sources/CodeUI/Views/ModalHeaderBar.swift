//
//  ModalHeaderBar.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct ModalHeaderBar: View {
    
    @Binding public var isPresented: Bool
    
    public var title: String?
//    public var showHandle: Bool
    
    public init(title: String?, /*showHandle: Bool = true,*/ isPresented: Binding<Bool>) {
        self.title = title
//        self.showHandle = showHandle
        self._isPresented = isPresented
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
//            if showHandle {
//                HandleView()
//                    .padding(15)
//            }
            HStack {
                Spacer()
                    .frame(width: 60, height: 60, alignment: .center)
                Spacer()
                if let title = title {
                    Text(title)
                        .padding(10)
                        .foregroundColor(.textMain)
                        .font(.appTitle)
                    Spacer()
                }
                Button {
                    isPresented.toggle()
                } label: {
                    Image.asset(.close)
                        .padding(20)
                }
            }
            .padding([.leading, .trailing], 10)
            .padding(.top, 20)
        }
    }
}

// MARK: - Previews -

struct ModalHeaderBar_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                ModalHeaderBar(title: "Give Kin", isPresented: .constant(true))
                Spacer()
            }
        }
    }
}
