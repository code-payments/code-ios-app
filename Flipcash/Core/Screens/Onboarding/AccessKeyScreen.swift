//
//  AccessKeyScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-04-13.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct AccessKeyScreen: View {
    
    @Bindable private var viewModel: OnboardingViewModel
    
    // MARK: - Init -
    
    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Spacer()
                
                VStack(alignment: .center, spacing: 30) {
                    AccessKey(
                        mnemonic: viewModel.inflightMnemonic,
                        url: .login(with: viewModel.inflightMnemonic)
                    )
                    .contextMenu {
                        Button(action: copy) {
                            Label("Copy", systemImage: SystemSymbol.doc.rawValue)
                        }
                    }
                    
                    Text("Your Access Key is the only way to access your account. Please keep it private and safe.")
                        .font(.appTextSmall)
                        .foregroundStyle(.textMain)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
                
                Spacer()
                
                CodeButton(
                    state: viewModel.accessKeyButtonState,
                    style: .filled,
                    title: "Save Access Key to Photos",
                    action: viewModel.saveToPhotosAction
                )
                
                Button("Wrote the 12 Words Down Instead?", action: viewModel.wroteDownAction)
                    .buttonStyle(.subtle)
                    .disabled(viewModel.accessKeyButtonState != .normal)
            }
            .ignoresSafeArea(.keyboard)
            .foregroundStyle(.textMain)
            .padding(20)
            .navigationTitle("Your Access Key")
            .navigationBarTitleDisplayMode(.inline)
        }
        .dialog(item: $viewModel.dialogItem)
    }
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = viewModel.inflightMnemonic.phrase
    }
}
