//
//  EnterUsernameScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import CodeServices

struct EnterUsernameScreen: View {
    
    @EnvironmentObject private var client: Client
    
    @State private var enteredUsername: String = ""
    
    private var canProceed: Bool {
        enteredUsername.count >= 4
    }
    
    // MARK: - Init -
    
    init() {
        
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 40) {
                Spacer()
                
                TextField("X Username", text: $enteredUsername)
                    .font(.appDisplayMedium)
                    .frame(maxWidth: .infinity)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .padding([.leading, .trailing], 0)
                
                Spacer()
                
                CodeButton( style: .filled, title: Localized.Action.next, disabled: !canProceed) {
                    
                }
            }
            .foregroundColor(.textMain)
            .frame(maxHeight: .infinity)
            .padding(20)
        }
        .navigationBarTitle(Text("What's Their Username?"), displayMode: .inline)
    }
}

#Preview {
    EnterUsernameScreen()
}
