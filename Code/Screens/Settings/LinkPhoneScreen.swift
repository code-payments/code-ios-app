//
//  LinkPhoneScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-03-15.
//

import SwiftUI
import CodeUI
import CodeServices

struct LinkPhoneScreen: View {
    
    @EnvironmentObject var bannerController: BannerController
    
    @ObservedObject private var session: Session
    
    @EnvironmentObject private var client: Client
    
    @State private var isPresentingLinkPhone = false
    @State private var isLoading = false
    
    private let overridePhoneLink: PhoneLink?
    
    private var isLinked: Bool {
        if let overridePhoneLink = overridePhoneLink {
            return overridePhoneLink.isLinked
        } else {
            return session.phoneLink?.isLinked == true
        }
    }
    
    private var verifiedPhone: Phone? {
        if let overridePhoneLink = overridePhoneLink {
            return overridePhoneLink.phone
        } else {
            return session.phoneLink?.phone
        }
    }
    
    // MARK: - Init -
    
    fileprivate init(session: Session, phoneLink: PhoneLink? = nil) {
        self.session = session
        self.overridePhoneLink = phoneLink
    }
    
    init(session: Session) {
        self.init(session: session, phoneLink: nil)
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading) {
                Spacer()
                VStack(alignment: .leading, spacing: 30) {
                    phoneImage()
                    title()
                        .font(.appDisplayMedium)
                    description()
                        .font(.appTextMedium)
                    
                }
                .foregroundColor(.textMain)
                Spacer()
                action()
            }
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationBarTitle(Text(Localized.Title.phoneNumber), displayMode: .inline)
        .sheet(isPresented: $isPresentingLinkPhone) {
            NavigationView {
                VerifyPhoneScreen(
                    isActive: $isPresentingLinkPhone,
                    showCloseButton: true,
                    viewModel: VerifyPhoneViewModel(
                        client: client,
                        bannerController: bannerController,
                        mnemonic: session.organizer.mnemonic,
                        completion: completePhoneVerification
                    )
                ) {
                    EmptyView()
                }
            }
        }
        .onAppear {
            Analytics.open(screen: .linkPhone)
            ErrorReporting.breadcrumb(.linkPhoneScreen)
            Task {
                try await session.updatePhoneLinkStatus()
            }
        }
    }
    
    @ViewBuilder private func phoneImage() -> some View {
        if isLinked {
            Image.asset(.telephoneFilled)
        } else {
            Image.asset(.telephoneOutline)
        }
    }
    
    @ViewBuilder private func action() -> some View {
        if isLinked, let phone = verifiedPhone {
            CodeButton(
                isLoading: isLoading,
                style: .subtle,
                title: Localized.Action.removeYourPhoneNumber
            ) {
                bannerController.show(
                    style: .error,
                    title: Localized.Prompt.Title.unlinkPhoneNumber,
                    description: Localized.Prompt.Description.unlinkPhoneNumber,
                    position: .bottom,
                    actions: [
                        .destructive(title: Localized.Action.removePhoneNumber) {
                            unlinkPhone(phone: phone)
                        },
                        .cancel(title: Localized.Action.cancel),
                    ]
                )
            }
        } else {
            CodeButton(
                isLoading: isLoading,
                style: .filled,
                title: Localized.Action.linkPhoneNumber
            ) {
                isPresentingLinkPhone.toggle()
            }
        }
    }
    
    @ViewBuilder func title() -> some View {
        if isLinked, let phone = verifiedPhone {
            Text(phone.national)
        } else {
            Text(Localized.Subtitle.noLinkedPhoneNumber)
        }
    }
    
    @ViewBuilder func description() -> some View {
        if isLinked {
            Text(Localized.Subtitle.linkedPhoneNumberDescription)
        } else {
            Text(Localized.Subtitle.noLinkedPhoneNumberDescription)
        }
    }
    
    // MARK: - Actions -
    
    private func unlinkPhone(phone: Phone) {
        isLoading.toggle()
        Task {
            try await session.unlinkAccount(from: phone)
            try await session.updatePhoneLinkStatus()
            isLoading = false
        }
    }
    
    private func completePhoneVerification(phone: Phone, code: String, mnemonic: MnemonicPhrase) async throws {
        try await session.updatePhoneLinkStatus()
        try await Task.delay(milliseconds: 500)
        isPresentingLinkPhone = false
    }
}

// MARK: - Previews -

struct LinkPhoneScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                LinkPhoneScreen(session: .mock, phoneLink: PhoneLink(phone: .mock, isLinked: true))
            }
            NavigationView {
                LinkPhoneScreen(session: .mock, phoneLink: PhoneLink(phone: .mock, isLinked: false))
            }
            NavigationView {
                LinkPhoneScreen(session: .mock)
            }
        }
        .environmentObjectsForSession()
    }
}
