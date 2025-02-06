//
//  ChangeRoomNameScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct ChangeRoomNameScreen: View {
    
    @ObservedObject private var viewModel: ChatViewModel
    
    @FocusState private var isFocused: Bool
    
    private let chatID: ChatID
    
    // MARK: - Init -
    
    init(chatID: ChatID, viewModel: ChatViewModel) {
        self.chatID = chatID
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(alignment: .leading, spacing: 40) {
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 15) {
                        TextField("Flipchat Name", text: $viewModel.enteredRoomName)
                            .focused($isFocused)
                            .font(.appDisplayMedium)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60) // Needs explicit height to avoid changing offset when scaling text down
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .textInputAutocapitalization(.words)
                            .minimumScaleFactor(0.5)
                            .multilineTextAlignment(.leading)
                            .padding([.leading, .trailing], 0)
                        
                        Text("Enter a name appropriate for all ages")
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .foregroundStyle(Color.textMain)
                    
                    Spacer()
                    
                    CodeButton(
                        state: viewModel.buttonStateEnterRoomName,
                        style: .filled,
                        title: "Save",
                        disabled: !viewModel.isEnteredRoomNameValid()
                    ) {
                        hideKeyboard()
                        viewModel.changeRoomName(chatID: chatID)
                    }
                }
                .foregroundColor(.textMain)
                .frame(maxHeight: .infinity)
                .padding(20)
            }
            .navigationBarTitle(Text(""), displayMode: .inline)
            .onAppear(perform: onAppear)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(action: viewModel.dismissChangeRoomName)
                }
            }
        }
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
    ChangeRoomNameScreen(chatID: .mock, viewModel: .mock)
}
