//
//  EnterRoomNumberScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import CodeServices

struct EnterRoomNumberScreen: View {
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var bannerController: BannerController
    
    @State private var isShowingChat: Bool = false
    
    @ObservedObject private var viewModel: ChatViewModel
    
    @FocusState private var isFocused: Bool
    
    // MARK: - Init -
    
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 40) {
                Spacer()
                
                TextField("Room Number", text: $viewModel.enteredRoomNumber)
                    .focused($isFocused)
                    .font(.appDisplayMedium)
                    .frame(maxWidth: .infinity)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numberPad)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .padding([.leading, .trailing], 0)
                
                Spacer()
                
                CodeButton(
                    state: viewModel.beginChatState,
                    style: .filled,
                    title: Localized.Action.next,
                    disabled: !viewModel.isEnteredRoomNumberValid()
                ) {
                    hideKeyboard()
                    viewModel.attemptEnterGroupChat()
                }
            }
            .onAppear(perform: onAppear)
            .foregroundColor(.textMain)
            .frame(maxHeight: .infinity)
            .padding(20)
        }
        .navigationBarTitle(Text("Enter Room Number"), displayMode: .inline)
    }
    
    private func onAppear() {
        showKeyboard()
    }
    
    private func showKeyboard() {
        isFocused = true
    }
    
    private func hideKeyboard() {
        isFocused = false
    }
}

#Preview {
    EnterRoomNumberScreen(viewModel: .mock)
}
