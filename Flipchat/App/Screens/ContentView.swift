//
//  ContentView.swift
//  Flipchat
//
//  Created by Dima Bart on 2024-09-24.
//

import SwiftUI
import CodeUI

struct ContentView: View {
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                Spacer()
                Text("Chat\nHere")
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.trailing)
                Spacer()
                CodeButton(style: .filled, title: "Next") {
                    
                }
            }
            .padding(20)
        }
    }
}

#Preview {
    ContentView()
}
