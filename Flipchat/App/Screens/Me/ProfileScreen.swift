//
//  ProfileScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-11-03.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct ProfileScreen: View {
    
    @EnvironmentObject var banners: Banners
    @Environment(\.dismiss) var dismiss
    
    @ObservedObject private var sessionAuthenticator: SessionAuthenticator
    @ObservedObject private var twitterController: TwitterController
    
    @State private var isShowingButtonSheet: Bool = false
    
    private let userID: UserID
    private let isSelf: Bool
    private let container: AppContainer
    private let chatController: ChatController
    
    @StateObject private var updateableUser: Updateable<UserProfileRow?>
    
    private var userProfile: UserProfileRow? {
        updateableUser.value
//        UserProfileRow(
//            serverID: UUID(),
//            displayName: "dima",
//            avatarURL: nil,
//            profile:
//                    .init(
//                socialID: "123456789",
//                username: "johnsmith",
//                displayName: "Jonh Smith",
//                bio: "Professional flourist that likes walks in the park and other activities and maybe long walks on the brach",
//                followerCount: 3625,
//                avatarURL: URL(string: "https://pbs.twimg.com/profile_images/1258717928503029761/NKN1Dd1p_400x400.jpg")!,
//                verificationType: .none
//            )
//        )
    }
    
    private var hasSocialProfile: Bool {
        userProfile?.profile != nil
    }
    
    private var socialID: String? {
        userProfile?.profile?.socialID
    }
    
    private var displayName: String {
        userProfile?.resolvedDisplayName ?? ""
    }
    
    private var username: String? {
        userProfile?.profile?.username
    }
    
    private var avatarURL: URL? {
        userProfile?.profile?.avatar?.original ?? userProfile?.avatarURL
    }
    
    private var avatarData: Data {
        userProfile?.serverID.data ?? Data([0, 0, 0, 0])
    }
    
    private var followerCount: Int {
        userProfile?.profile?.followerCount ?? 0
    }
    
    private var bio: String? {
        userProfile?.profile?.bio
    }
    
    private var verificationType: VerificationType {
        userProfile?.profile?.verificationType ?? .none
    }
    
//    private var isTwitterLinked: Bool {
//        if case .authorized = twitterController.state {
//            return true
//        } else {
//            return false
//        }
//    }
    
    // MARK: - Init -
    
    init(userID: UserID, isSelf: Bool, state: AuthenticatedState, container: AppContainer) {
        self.userID = userID
        self.isSelf = isSelf
        self.container = container
        self.sessionAuthenticator = container.sessionAuthenticator
        self.twitterController = state.twitterController
        let chatController = state.chatController
        
        self._updateableUser = .init(wrappedValue: Updateable {
            try? chatController.getUserProfile(userID: userID)
        })
        
        self.chatController = chatController
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                navigationBar()
                
                VStack(spacing: 20) {
                    UserGeneratedAvatar(
                        url: avatarURL,
                        data: avatarData,
                        diameter: 120
                    )
                    .padding(.top, 10)
                    
                    if isSelf {
                        if hasSocialProfile {
                            profileDetails()
                        } else {
                            nameRow()
                            CodeButton(
                                style: .filled,
                                image: Image.asset(.twitter),
                                title: "Connect Your X Account",
                                action: connectTwitter
                            )
                            .padding(.top, 20)
                        }
                    } else {
                        profileDetails()
                    }
                }
                .padding(20)
                
                Spacer()
            }
        }
        .buttonSheet(isPresented: $isShowingButtonSheet) {
            if hasSocialProfile {
                Action.standard(image: .asset(.twitter), title: "Disconnect X") {
                    showDisconnectTwitterConfirmation()
                }
            }
            
            Action.standard(systemImage: "trash", title: "Delete My Account") {
                showDeleteAccountConfirmation()
            }
        }
    }
    
    @ViewBuilder private func nameRow() -> some View {
        MemberNameLabel(
            size: .large,
            showLogo: hasSocialProfile,
            name: displayName,
            verificationType: verificationType
        )
    }
    
    @ViewBuilder private func profileDetails() -> some View {
        VStack(spacing: 40) {
            VStack {
                nameRow()
                
                if hasSocialProfile {
                    if let username {
                        Text("@\(username)")
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                            .transition(transitionForSocialProfile())
                    }
                }
            }
            
            if hasSocialProfile {
                VStack(spacing: 8) {
                    Text("\(followerCount.formattedAbbreviated) \(followerCount == 1 ? "follower" : "followers")")
                    if let bio {
                        Text(bio)
                    }
                }
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 30)
                .transition(transitionForSocialProfile())
            }
            
            if !isSelf && hasSocialProfile {
                CodeButton(
                    style: .filled,
                    image: Image.asset(.twitter),
                    title: "Open Profile on X",
                    action: openProfile
                )
                .transition(transitionForSocialProfile())
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasSocialProfile)
        .multilineTextAlignment(.center)
    }
    
    @ViewBuilder private func navigationBar() -> some View {
        NavBar(title: "") {} leading: {} trailing: {
            if isSelf {
                Button {
                    isShowingButtonSheet.toggle()
                } label: {
                    Image.asset(.more)
                        .padding(.vertical, 10)
                        .padding(.leading, 20)
                        .padding(.trailing, 30)
                }
            } else {
                Button {
                    dismiss()
                } label: {
                    Image.asset(.close)
                        .padding(20)
                }
            }
        }
    }
    
    // MARK: - Actions -
    
    private func connectTwitter() {
        Task {
            try await twitterController.authorize()
        }
    }
    
    private func openProfile() {
        guard let username else {
            return
        }
        
        URL.profileFor(username: username).openWithApplication()
    }
    
    private func showDisconnectTwitterConfirmation() {
        banners.show(
            style: .error,
            title: "Disconnect Your X Account?",
            description: "You will no longer have a profile picture or connected X account",
            position: .bottom,
            actions: [
                .destructive(title: "Disconnect Your X Account") {
                    guard let socialID else { return }
                    Task {
                        try await twitterController.unlink(socialID: socialID)
                    }
                },
                .cancel(title: "Cancel") {},
            ]
        )
    }
    
    private func showDeleteAccountConfirmation() {
        banners.show(
            style: .error,
            title: "Permanently Delete Account?",
            description: "This will permanently delete your Flipchat account",
            position: .bottom,
            actions: [
                .destructive(title: "Permanently Delete My Account") {
                    sessionAuthenticator.logout()
                },
                .cancel(title: "Cancel") {},
            ]
        )
    }
    
    // MARK: - Transition -
    
    private func transitionForSocialProfile() -> AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }
}

#Preview {
//    ProfileScreen(
//        userID: .mock,
//        isSelf: true,
//        state: .mock,
//        container: .mock
//    )
    NavigationStack {
        ProfileScreen(
            userID: .mock,
            isSelf: true,
            state: .mock,
            container: .mock
        )
    }
    .environmentObjectsForSession()
}
