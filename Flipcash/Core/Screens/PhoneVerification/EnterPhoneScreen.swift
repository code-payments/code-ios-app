//
//  EnterPhoneScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-01-11.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct EnterPhoneScreen<VM: PhoneVerifying>: View {

    @State private var isShowingRegionSelection = false

    @Bindable private var viewModel: VM

    @FocusState private var isFocused: Bool

    // MARK: - Init -

    init(viewModel: VM) {
        self.viewModel = viewModel
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 15) {
                Spacer()
                InputContainer(size: .regular) {
                    HStack(spacing: 0) {
                        Button {
                            isShowingRegionSelection = true
                        } label: {
                            HStack(spacing: 10) {
                                Flag(style: viewModel.regionFlagStyle)
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
                            CountryCodeSelectionScreen(
                                isPresented: $isShowingRegionSelection,
                                didSelectRegion: didSelectRegion
                            )
                        }

                        TextField("Phone Number", text: viewModel.adjustingPhoneNumberBinding)
                            .font(.appTextXL)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .multilineTextAlignment(.leading)
                            .padding([.leading, .trailing], 15)
                            .focused($isFocused)
                    }
                }

                Text("Please enter your phone number to continue")
                    .foregroundStyle(.textSecondary)
                    .font(.appTextSmall)
                    .multilineTextAlignment(.center)

                Spacer()

                CodeButton(
                    state: viewModel.sendCodeButtonState,
                    style: .filled,
                    title: "Next",
                    disabled: !viewModel.canSendVerificationCode
                ) {
                    isFocused = false
                    viewModel.sendPhoneNumberCodeAction()
                }
            }
            .padding(20)
            .foregroundStyle(.textMain)
        }
        .dialog(item: $viewModel.dialogItem)
        .toolbarTitleDisplayMode(.inline)
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            isFocused = true
        }
        .onChange(of: viewModel.enteredPhone) { _, _ in
            // Advance as soon as the number is valid — a completed or pasted
            // number submits without a manual "Next" tap, mirroring the code
            // screen's auto-submit. The button-state guard stops a re-fire while
            // a request is already in flight.
            if viewModel.canSendVerificationCode, viewModel.sendCodeButtonState == .normal {
                isFocused = false
                viewModel.sendPhoneNumberCodeAction()
            }
        }
    }

    // MARK: - Actions -

    private func didSelectRegion(region: Region) {
        viewModel.setRegion(region)
        isShowingRegionSelection = false
    }
}
