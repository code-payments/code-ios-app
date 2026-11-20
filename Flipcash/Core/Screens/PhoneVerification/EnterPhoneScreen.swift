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

    private let copy: PhoneVerificationCopy

    // MARK: - Init -

    init(viewModel: VM, copy: PhoneVerificationCopy = .standard) {
        self.viewModel = viewModel
        self.copy = copy
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            Group {
                if let header = copy.entryHeader {
                    OnboardingStepLayout(header: header) {
                        VStack(alignment: .leading, spacing: OnboardingStepMetrics.formSpacing) {
                            VStack(alignment: .leading, spacing: OnboardingStepMetrics.labelToField) {
                                if let fieldLabel = copy.entryFieldLabel {
                                    OnboardingFieldLabel(title: fieldLabel)
                                }
                                phoneField
                            }
                            PhoneEntryHint(showsError: viewModel.showsInvalidPhoneHint, copy: copy)
                        }
                    } action: {
                        nextButton
                    }
                } else {
                    VStack(spacing: 15) {
                        Spacer()
                        phoneField
                        PhoneEntryHint(showsError: viewModel.showsInvalidPhoneHint, copy: copy)
                        Spacer()
                        nextButton
                    }
                    .padding(20)
                }
            }
            .foregroundStyle(.textMain)
        }
        .dialog(item: $viewModel.dialogItem)
        .toolbarTitleDisplayMode(.inline)
        .focusAfterPush($isFocused)
        .onChange(of: viewModel.enteredPhone) { _, _ in
            // Advance as soon as the number is valid — a completed or pasted
            // number submits without a manual "Next" tap, mirroring the code
            // screen's auto-submit. The button-state guard stops a re-fire while
            // a request is already in flight.
            //
            // Neither submit path drops focus. Closing the keyboard here zeroes
            // this screen's keyboard inset, and the code screen then raises a
            // keyboard of the same height while this one is off screen. Back
            // returns under that keyboard with the inset still zero, which puts
            // Next behind the keypad.
            if viewModel.canSendVerificationCode, viewModel.sendCodeButtonState == .normal {
                viewModel.sendPhoneNumberCodeAction()
            }
        }
    }

    // MARK: - Subviews -

    private var phoneField: some View {
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
    }

    private var nextButton: some View {
        CodeButton(
            state: viewModel.sendCodeButtonState,
            style: .filled,
            title: "Next",
            disabled: !viewModel.canSendVerificationCode
        ) {
            viewModel.sendPhoneNumberCodeAction()
        }
    }

    // MARK: - Actions -

    private func didSelectRegion(region: Region) {
        viewModel.setRegion(region)
        isShowingRegionSelection = false
    }
}

private struct PhoneEntryHint: View {

    let showsError: Bool
    let copy: PhoneVerificationCopy

    var body: some View {
        if copy == .standard {
            hint
                .font(.appTextSmall)
                .multilineTextAlignment(.center)
        } else {
            hint
                .font(.appTextBody)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hint: some View {
        Text(showsError ? "Phone number invalid" : copy.entryHint)
            .foregroundStyle(showsError ? .textError : .textSecondary)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: showsError)
    }
}
