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
    @EnvironmentObject private var bannerController: BannerController
    
    @State private var enteredUsername: String = ""
    
    @State private var isShowingChat: Bool = false
    
    @ObservedObject private var viewModel: DirectMessageViewModel
    
    // MARK: - Init -
    
    init(viewModel: DirectMessageViewModel) {
        self.viewModel = viewModel
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
                
                CodeButton(
                    state: viewModel.beginChatState,
                    style: .filled,
                    title: Localized.Action.next,
                    disabled: !viewModel.isValid(username: enteredUsername)
                ) {
                    viewModel.attemptChat(with: enteredUsername)
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
    EnterUsernameScreen(viewModel: .mock)
}
