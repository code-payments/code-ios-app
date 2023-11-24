//
//  ContactsScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-18.
//

import SwiftUI
import CodeUI
import CodeServices

struct ContactsScreen: View {
    
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @ObservedObject private var inviteController: InviteController
    @ObservedObject private var contactsController: ContactsController
    
    @Binding public var isPresented: Bool
    
    @State private var searchText = ""
    @State private var isFocused = false
    
    @StateObject var messageController = MessageController()
    
    private var isSearching: Bool {
        !searchText.isEmpty
    }
    
    private var isSearchNumericOnly: Bool {
        if isSearching {
            var phoneString = searchText
            if phoneString.first == "+" {
                phoneString = phoneString.replacingOccurrences(of: "+", with: "")
            }
            return CharacterSet(charactersIn: phoneString).subtracting(.decimalDigits).isEmpty
        } else {
            return false
        }
    }
    
    private var searchPhoneNumber: Phone? {
        Phone(searchText)
    }
    
    private var inviteCount: Int {
        inviteController.inviteCount
    }
    
    private var displayContacts: [Contact] {
        var contacts = contactsController.contacts

        if !searchText.isEmpty {
            let term = searchText.lowercased()
            contacts = contacts.filter {
                $0.displayName.lowercased().contains(term) ||
                $0.phoneNumber.e164.contains(term)
            }
        }

        return contacts
//        (0..<10).flatMap { id in
//            [
//                Contact(
//                    id: "1-\(id)",
//                    firstName: "John",
//                    lastName: "Smith",
//                    company: nil,
//                    phoneNumber: Phone("9055671234")!,
//                    state: .invited
//                ),
//                Contact(
//                    id: "2-\(id)",
//                    firstName: nil,
//                    lastName: nil,
//                    company: "Jonny Rockets LTD",
//                    phoneNumber: Phone("4169387483")!,
//                    state: .registered
//                ),
//                Contact(
//                    id: "3-\(id)",
//                    firstName: "Walter",
//                    lastName: nil,
//                    company: nil,
//                    phoneNumber: Phone("6474832057")!
//                ),
//            ]
//        }
    }
    
    private let phoneFormatter = PhoneFormatter()
    
    // MARK: - Init -
    
    public init(inviteController: InviteController, contactsController: ContactsController, isPresented: Binding<Bool>) {
        self.inviteController = inviteController
        self.contactsController = contactsController
        self._isPresented = isPresented
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            if contactsController.status != .authorized {
                authorizeView()
            } else {
                contactList()
            }
        }
        .onChange(of: inviteController.inviteCount) { _ in
            inviteController.markSeen()
        }
        .onAppear {
            Analytics.open(screen: .contacts)
            ErrorReporting.breadcrumb(.contactsScreen)
            
            inviteController.fetchInvites()
            inviteController.markSeen()
            
            if contactsController.status == .authorized {
                contactsController.fetchContactMetadata()
            }
        }
    }
    
    @ViewBuilder func authorizeView() -> some View {
        VStack(alignment: .leading) {
            ModalHeaderBar(title: Localized.Title.inviteFriend, isPresented: $isPresented)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 60) {
                Image.asset(.inviteLetter)
                VStack(alignment: .leading, spacing: 20) {
                    Text(Localized.Subtitle.inviteCount(inviteCount))
                        .font(.appDisplayMedium)
                    Text(
                        Localized.Subtitle.youHaveInvitesLeft(inviteCount)
                    )
                    .font(.appTextMedium)
                }
            }
            .foregroundColor(.textMain)
            .padding(20)
            
            Spacer()
            
            CodeButton(
                style: .filled,
                title: Localized.Action.allowContacts,
                action: authorizeAccessToContacts
            )
            .padding(20)
        }
    }
    
    @ViewBuilder func contactList() -> some View {
        VStack(spacing: 0) {
            ModalHeaderBar(title: Localized.Subtitle.youHaveInvites(inviteCount), isPresented: $isPresented)
            
            SearchBar(content: $searchText, isActive: $isFocused) { searchBar in
                searchBar.placeholder = Localized.Subtitle.searchForContacts
            }
            .padding([.leading, .trailing], 10)
            
            let contacts = displayContacts
            if contacts.isEmpty {
                if contactsController.isFetchingContacts {
                    loadingView()
                } else {
                    if isSearching && isSearchNumericOnly {
                        inviteStrangerView()
                    } else {
                        Spacer()
                    }
                }
            } else {
                ScrollBox(color: .backgroundMain) {
                    LazyTable(contentPadding: .scrollBox) {
                        ForEach(contacts, id: \.uniqueIdentifier) { contact in
                            row(contact: contact)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder func loadingView() -> some View {
        Spacer()
        VStack {
            Text(Localized.Subtitle.organizingContacts)
                .font(.appTextSmall)
                .foregroundColor(.textMain)
            LoadingView(color: .textMain)
        }
        Spacer()
    }
    
    private var flagEmoji: String {
        guard let flag = searchPhoneNumber?.unicodeFlag else {
            return ""
        }
        
        return "\(flag) "
    }
    
    @ViewBuilder func inviteStrangerView() -> some View {
        VStack(spacing: 20) {
            Text(Localized.Subtitle.phoneNotInContacts)
                .font(.appTextSmall)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
            
            CodeButton(
                style: .filled,
                title: "\(Localized.Action.invite) \(flagEmoji)\(phoneFormatter.format(searchText))"
            ) {
                inviteSearchedAction()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        Spacer()
    }
    
    @ViewBuilder func row(contact: Contact) -> some View {
        HStack(spacing: 12) {
            InitialAvatarView(size: 44, initials: contact.initials)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(contact.displayName)
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                Text(contact.phoneNumber.national)
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
            }
            .padding([.top, .bottom], 15)
            
            Spacer()
            
            accessoryView(contact: contact)
        }
        .padding(.trailing, 20)
        .vSeparator(color: .rowSeparator)
        .padding(.leading, 20)
    }
    
    @ViewBuilder func accessoryView(contact: Contact) -> some View {
        switch contact.state {
        case .invited:
            Button {
                inviteAction(phone: contact.phoneNumber)
            } label: {
                TextBubble(style: .outline, text: Localized.Action.remind)
            }
            
        case .registered:
            HStack(spacing: 6) {
                Image.asset(.checkmark)
                    .renderingMode(.template)
                    .foregroundColor(.textSuccess)
                Text(Localized.Subtitle.onCode)
                    .foregroundColor(Color.textMain)
                    .font(.appTextSmall)
            }
            
        case .unknown:
            Button {
                inviteAction(phone: contact.phoneNumber)
            } label: {
                TextBubble(style: .filled, text: Localized.Action.invite)
            }
        }
    }
    
    // MARK: - Actions -
    
    private func authorizeAccessToContacts() {
        if contactsController.status == .notDetermined {
            Task {
                try await contactsController.requestAccessIfNeeded()
            }
        } else {
            showPermissionError()
        }
    }
    
    private func inviteSearchedAction() {
        guard let phone = searchPhoneNumber else {
            showInvalidPhoneError()
            return
        }
        
        inviteAction(phone: phone)
    }
    
    private func inviteAction(phone: Phone) {
        guard inviteCount > 0 else {
            showNoInvitesError()
            return
        }
        
        let link = URL.downloadCode.absoluteString
        let body = Localized.Subtitle.inviteText(link)
        
        messageController.presentMessage(to: phone.e164, body: body) { result in
            switch result {
            case .sent:
                Task {
                    do {
                        try await whitelist(phone: phone)
                        contactsController.fetchContactMetadata()
                    } catch ErrorSendInvite.alreadyInvited {
                        // Do nothing
                    } catch {
                        showInvitationError()
                    }
                }
                
            case .failed:
                showInvitationError()
                
            case .cancelled:
                break
            }
        }
    }
    
    private func whitelist(phone: Phone) async throws {
        try await inviteController.whitelist(phone: phone)
    }
    
    // MARK: - Errors -
    
    private func showPermissionError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.contactsAccessRequired,
            description: Localized.Error.Description.contactsAccessRequired,
            actions: [
                .cancel(title: Localized.Action.ok),
                .standard(title: Localized.Action.openSettings) {
                    URL.openSettings()
                }
            ]
        )
    }
    
    private func showInvitationError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.invitationFailed,
            description: Localized.Error.Description.invitationFailed,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showNoInvitesError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.noInvitesLeft,
            description: Localized.Error.Description.noInvitesLeft,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showInvalidPhoneError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.invalidInvitePhone,
            description: Localized.Error.Description.invalidInvitePhone,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}

// MARK: - Previews -

struct ContactsScreen_Previews: PreviewProvider {
    static var previews: some View {
        ContactsScreen(
            inviteController: .mock,
            contactsController: .mock,
            isPresented: .constant(true)
        )
        .environmentObjectsForSession()
    }
}
