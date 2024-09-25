//
//  VerifyPhoneScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-01-11.
//

import SwiftUI
import CodeUI
import CodeServices
import SwiftUIIntrospect

struct VerifyPhoneScreen<Content>: View where Content: View {
    
    @Binding private var isActive: Bool
    
    @State private var isShowingRegionSelection = false
    
    @State private var textField: UITextField?
    
    @StateObject private var viewModel: VerifyPhoneViewModel
    
    private let textFieldDelegate = TextFieldDelegate()
    private let showCloseButton: Bool
    private let destinationContent: () -> Content
    
    // MARK: - Init -
    
    init(isActive: Binding<Bool>, showCloseButton: Bool, viewModel: @autoclosure @escaping () -> VerifyPhoneViewModel, @ViewBuilder destinationContent: @escaping () -> Content) {
        self._isActive   = isActive
        self.showCloseButton = showCloseButton
        self._viewModel = StateObject(wrappedValue: viewModel())
        self.destinationContent = destinationContent
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 15) {
                Flow(isActive: $viewModel.isShowingConfirmCodeScreen) {
                    ConfirmPhoneScreen(
                        isActive: $isActive,
                        showCloseButton: showCloseButton,
                        viewModel: viewModel
                    )
                    LazyView(
                        destinationContent()
                    )
                }
                
                Spacer()
                InputContainer(size: .regular) {
                    HStack(spacing: 0) {
                        Button {
                            isShowingRegionSelection = true
                        } label: {
                            HStack(spacing: 10) {
                                Flag(style: viewModel.countryFlagStyle)
                                Text(viewModel.countryCode)
                                    .font(.appTextXL)
                            }
                            .padding([.leading, .trailing], 15)
                            .frame(maxHeight: .infinity)
                        }
                        .background(
                            RectEdgeShape(edge: .right)
                                .strokeBorder(Metrics.inputFieldStrokeColor(highlighted: false), lineWidth: Metrics.inputFieldBorderWidth(highlighted: false))
                        )
                        .sheet(isPresented: $isShowingRegionSelection) {
                            RegionSelectionScreen(
                                isPresented: $isShowingRegionSelection,
                                didSelectRegion: didSelectRegion
                            )
                        }
                        
                        TextField(Localized.Title.phoneNumber, text: viewModel.adjustingPhoneNumberBinding)
                            .font(.appTextXL)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .multilineTextAlignment(.leading)
                            .introspect(.textField, on: .iOS(.v16, .v17, .v18)) { field in
                                field.delegate = textFieldDelegate
                                textField = field
                            }
                        
                            // TODO: Convert view model to FocusState
                            //.focused(<#T##condition: FocusState<Bool>.Binding##FocusState<Bool>.Binding#>)
                            .padding([.leading, .trailing], 15)
                    }
                }
                
                Text(Localized.Subtitle.phoneVerificationDescription)
                    .foregroundColor(.textSecondary)
                    .font(.appTextSmall)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                CodeButton(
                    state: viewModel.sendCodeButtonState,
                    style: .filled,
                    title: Localized.Action.next,
                    disabled: !viewModel.canSendVerificationCode
                ) {
                    viewModel.sendCode()
                }
            }
            .padding(20)
            .foregroundColor(.textMain)
        }
        .navigationBarTitle(Text(Localized.Title.enterPhoneNumber), displayMode: .inline)
        .if(showCloseButton) { $0
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton {
                        isActive.toggle()
                    }
                }
            }
        }
        .onAppear {
            Analytics.open(screen: .verifyPhone)
            ErrorReporting.breadcrumb(.verifyPhoneScreen)
            Task {
                // Currently overloaded to imply that this
                // view is presented modally which has smaller
                // delay requirements for presenting the keyboard
                if showCloseButton {
                    try await Task.delay(milliseconds: 100)
                } else {
                    try await Task.delay(milliseconds: 500)
                }
                viewModel.isFocused = true
            }
        }
        .onChange(of: viewModel.isFocused) { isFocused in
            if isFocused {
                textField?.becomeFirstResponder()
            } else {
                _ = textField?.resignFirstResponder()
            }
        }
    }
    
    // MARK: - Actions -
    
    private func didSelectRegion(region: Region) {
        viewModel.changeRegion(region: region)
        isShowingRegionSelection = false
    }
}

// MARK: - TextField Delegate -

private class TextFieldDelegate: NSObject, UITextFieldDelegate {
    
    override init() {
        super.init()
    }
    
    func textFieldDidChangeSelection(_ textField: UITextField) {
        let p = textField.endOfDocument
        textField.selectedTextRange = textField.textRange(from: p, to: p)
    }
}

// MARK: - Previews -

struct VerifyPhoneScreen_Previews: PreviewProvider {
    static var previews: some View {
        VerifyPhoneScreen(
            isActive: .constant(true),
            showCloseButton: false,
            viewModel: VerifyPhoneViewModel(
                client: .mock,
                bannerController: .mock,
                mnemonic: .mock,
                completion: { _, _, _ in }
            )
        ) {
            EmptyView()
        }
        .preferredColorScheme(.dark)
    }
}
