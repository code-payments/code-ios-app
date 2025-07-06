//
//  EnterPoolNameScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-06-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct EnterPoolNameScreen: View {
    
    @Binding var isPresented: Bool
    
    @ObservedObject private var viewModel: PoolViewModel
    
    @FocusState private var isFocused: Bool
    
    @State private var didShowKeyboard: Bool = false
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, viewModel: PoolViewModel) {
        self._isPresented = isPresented
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.createPoolPath) {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 0) {
                    
                    Spacer()
                    
                    TextField("", text: $viewModel.enteredPoolName, prompt: Text("Question"), axis: .vertical)
                        .lineLimit(1...)
                        .focused($isFocused)
                        .font(.appDisplaySmall)
                        .foregroundStyle(Color.textMain)
                        .multilineTextAlignment(.center)
                        .truncationMode(.head)
                        .textInputAutocapitalization(.sentences)
                        .padding([.leading, .trailing], 0)
                    
                    Spacer()
                    
                    VStack(spacing: 10) {
                        Text("Pose a Yes or No question")
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textSecondary)
                        
//                        Text("\"Is Johnny going to hit a home run?\"")
//                            .font(.appTextSmall)
//                            .foregroundStyle(Color.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    
                    Spacer()
                    
                    CodeButton(
                        style: .filled,
                        title: "Next",
                        disabled: !viewModel.isEnteredPoolNameValid
                    ) {
                        hideKeyboard()
                        viewModel.submitPoolNameAction()
                    }
                }
                .foregroundColor(.textMain)
                .frame(maxHeight: .infinity)
                .padding(20)
            }
            .onAppear(perform: onAppear)
            .navigationTitle("Pose a Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .navigationDestination(for: CreatePoolPath.self) { path in
                switch path {
                case .enterPoolAmount:
                    EnterPoolAmountScreen(viewModel: viewModel)
                case .poolSummary:
                    PoolSummaryScreen(viewModel: viewModel)
                }
            }
        }
    }
    
    private func onAppear() {
        if !didShowKeyboard {
            didShowKeyboard = true
            showKeyboard()
        }
    }
    
    private func showKeyboard() {
        isFocused = true
    }
    
    private func hideKeyboard() {
        isFocused = false
    }
}
