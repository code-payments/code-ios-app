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

    /// The link's 44 pt box already holds about 12 pt under its text; 8 more puts the text 20 above
    /// the safe area, where a capsule's bottom edge sits on the other onboarding screens.
    private static let bottomPaddingUnderLink: CGFloat = 8
    
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
                
                VStack(spacing: Metrics.buttonGap) {
                    Button(action: viewModel.saveToPhotosAction) {
                        ButtonStateLabel("Save Access Key to Photos", state: viewModel.accessKeyButtonState)
                    }
                    .buttonStyle(.filled)
                    .disabled(!viewModel.accessKeyButtonState.isNormal)

                    Button("Wrote the 12 Words Down Instead?", action: viewModel.wroteDownAction)
                        .buttonStyle(.textLink)
                        .disabled(viewModel.accessKeyButtonState != .normal)
                }
            }
            .ignoresSafeArea(.keyboard)
            .foregroundStyle(.textMain)
            .padding([.horizontal, .top], 20)
            .padding(.bottom, Self.bottomPaddingUnderLink)
            .navigationTitle("Your Access Key")
            .toolbarTitleDisplayMode(.inline)
        }
        .dialog(item: $viewModel.dialogItem)
    }
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = viewModel.inflightMnemonic.phrase
    }
}
