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

    @Bindable private var coordinator: OnrampCoordinator

    @FocusState private var isFocused: Bool

    // MARK: - Init -

    init(coordinator: OnrampCoordinator) {
        self.coordinator = coordinator
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
                                Flag(style: coordinator.regionFlagStyle)
                                Text(coordinator.countryCode)
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

                        TextField("Phone Number", text: coordinator.adjustingPhoneNumberBinding)
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
                    .foregroundColor(.textSecondary)
                    .font(.appTextSmall)
                    .multilineTextAlignment(.center)

                Spacer()

                CodeButton(
                    state: coordinator.sendCodeButtonState,
                    style: .filled,
                    title: "Next",
                    disabled: !coordinator.canSendVerificationCode
                ) {
                    isFocused = false
                    coordinator.sendPhoneNumberCodeAction()
                }
            }
            .padding(20)
            .foregroundColor(.textMain)
        }
        .dialog(item: $coordinator.dialogItem)
        .navigationTitle("Verify Phone Number")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isFocused = true
        }
    }

    // MARK: - Actions -

    private func didSelectRegion(region: Region) {
        coordinator.setRegion(region)
        isShowingRegionSelection = false
    }
}
