//
//  EnterPhoneScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-01-11.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct EnterPhoneScreen: View {

    @State private var isShowingRegionSelection = false

    @Bindable private var onrampCoordinator: OnrampCoordinator

    @FocusState private var isFocused: Bool

    // MARK: - Init -

    init(onrampCoordinator: OnrampCoordinator) {
        self.onrampCoordinator = onrampCoordinator
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
                                Flag(style: onrampCoordinator.regionFlagStyle)
                                Text(onrampCoordinator.countryCode)
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

                        TextField("Phone Number", text: onrampCoordinator.adjustingPhoneNumberBinding)
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
                    state: onrampCoordinator.sendCodeButtonState,
                    style: .filled,
                    title: "Next",
                    disabled: !onrampCoordinator.canSendVerificationCode
                ) {
                    isFocused = false
                    onrampCoordinator.sendPhoneNumberCodeAction()
                }
            }
            .padding(20)
            .foregroundStyle(.textMain)
        }
        .dialog(item: $onrampCoordinator.dialogItem)
        .navigationTitle("Verify Phone Number")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isFocused = true
        }
    }

    // MARK: - Actions -

    private func didSelectRegion(region: Region) {
        onrampCoordinator.setRegion(region)
        isShowingRegionSelection = false
    }
}
