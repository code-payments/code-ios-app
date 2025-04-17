//
//  SessionAuthenticator.swift
//  Code
//
//  Created by Dima Bart on 2021-11-04.
//

import Foundation
import FlipcashCore
import FlipcashUI

@MainActor
final class SessionAuthenticator: ObservableObject {
    
    let accountManager: AccountManager
    
    @Published private(set) var loginButtonState: ButtonState = .normal
    @Published private(set) var isUnlocked: Bool = false
    @Published private(set) var state: AuthenticationState = .migrating
    
    var isLoggedIn: Bool {
        if case .loggedIn = state {
            return true
        } else {
            return false
        }
    }
    
    private let container: Container
    private let client: Client
    private let flipClient: FlipClient
    
    // MARK: - Init -
    
    init(container: Container) {
        self.container      = container
        self.client         = container.client
        self.flipClient     = container.flipClient
        self.accountManager = container.accountManager
        
        // Update launch state.
        // This is a fresh install.
        if UserDefaults.launchCount == nil {
            trace(.note, components: "First launch...")
        }
        
        UserDefaults.launchCount = (UserDefaults.launchCount ?? 0) + 1
        trace(.note, components: "Launch count: \(UserDefaults.launchCount!)")
        
        initializeState { userAccount in
            let initializedAccount = InitializedAccount(
                keyAccount: userAccount.keyAccount,
                userID: userAccount.userID
            )
            
            self.completeLogin(with: initializedAccount)
        }
    }
    
    private func initializeState(count: Int = 0, didAuthenticate: @escaping (UserAccount) -> Void) {
        trace(.warning)
        
        let userAccount = accountManager.fetchCurrentUserAccount()
        if let userAccount = userAccount {
            didAuthenticate(userAccount)
            
            // Inserting a new version of this key account
            // will update the `lastSeen` date and the
            // device name that is currently using it.
            accountManager.upsert(keyAccount: userAccount.keyAccount)
            
        } else {
            
            if !accountManager.fetchHistorical().isEmpty {
                state = .pending
            } else {
                state = .loggedOut
                
                // Only attempt to recover if there was an
                // account that was previous already logged in
                if UserDefaults.wasLoggedIn == true {
                    
                    // Try a total of 6 times, first attempt +
                    // 5 more retries after that
                    if count <= 5 {
                        
                        // It's possible the keychain credentials
                        // haven't been decoded yet and aren't
                        // available. We'll wait 1 second and
                        // retry a few times.
                        Task {
                            try await Task.delay(seconds: 1)
                            let nextCount = count + 1
                            initializeState(
                                count: nextCount,
                                didAuthenticate: didAuthenticate
                            )
                            
//                            ErrorReporting.breadcrumb(
//                                name: "Retrying login",
//                                metadata: ["count": "\(nextCount)"],
//                                type: .process
//                            )
                        }
                        
                    } else {
//                        Analytics.unintentialLogout()
                    }
                }
            }
        }
    }
    
    // MARK: - Session -
    
    private func createSessionContainer(container: Container, initializedAccount: InitializedAccount) -> Session {
        let session = Session(
            container: container,
            owner: initializedAccount.owner,
            userID: initializedAccount.userID
        )
        
//        session.delegate = self
        
        return session
    }
    
    // MARK: - Actions -
    
    func createAccountAction() {
        
    }
    
    // MARK: - Login -
    
    func initialize(using mnemonic: MnemonicPhrase, isRegistration: Bool) async throws -> InitializedAccount {
        loginButtonState = .loading
        defer {
            loginButtonState = .normal
        }
        
        let derivedKey: DerivedKey = .derive(
            using: .primary(),
            mnemonic: mnemonic
        )
        
        let keyAccount = KeyAccount(
            mnemonic: mnemonic,
            derivedKey: derivedKey
        )
        
        let cluster = AccountCluster(authority: derivedKey)
        
        do {
            let userID: UserID
            let userFlags: UserFlags
            
            if isRegistration {
                // 1. Create VM accounts first
                try await client.createAccounts(with: cluster)
                
                // 2. Register accounts with flipcash
                userID    = try await flipClient.register(owner: keyAccount.owner)
                userFlags = try await flipClient.fetchUserFlags(userID: userID, owner: keyAccount.owner)
            } else {
                userID    = try await flipClient.login(owner: keyAccount.owner)
                userFlags = try await flipClient.fetchUserFlags(userID: userID, owner: keyAccount.owner)
            }
            
            accountManager.set(
                keyAccount: keyAccount,
                userID: userID
            )
            
            trace(.note, components: "Owner: \(keyAccount.ownerPublicKey)")
            
            return InitializedAccount(
                keyAccount: keyAccount,
                userID: userID
            )
            
        } catch {
//            ErrorReporting.captureError(error)
            throw error
        }
    }
    
    func completeLogin(with initializedAccount: InitializedAccount) {
        trace(.note, components:
            "Owner: \(initializedAccount.keyAccount.ownerPublicKey)"
        )
        
        let session = createSessionContainer(
            container: container,
            initializedAccount: initializedAccount
        )
        
        state = .loggedIn(session)
        UserDefaults.wasLoggedIn = true
        
//        Analytics.setIdentity(initializedAccount.user)
    }
    
    func deleteAndLogout() {
        if case .loggedIn(let session) = state {
            accountManager.delete(ownerPublicKey: session.owner.authorityPublicKey)
            logout()
        }
    }
    
    func logout() {
        if case .loggedIn(let session) = state {
            session.prepareForLogout()
        }
        
        accountManager.resetForLogout()
        
        state = .loggedOut
        UserDefaults.wasLoggedIn = false
        
        trace(.note, components: "Logged out")
    }
}

// MARK: - UserDefaults -

extension UserDefaults {
    
    @Defaults(.launchCount)
    fileprivate static var launchCount: Int?
    
    @Defaults(.wasLoggedIn)
    fileprivate static var wasLoggedIn: Bool?
}

// MARK: - SessionDelegate -

extension SessionAuthenticator: SessionDelegate {
    func didDetectUnlockedAccount() {
        if !isUnlocked {
            isUnlocked = true
        }
    }
}

// MARK: - Errors -

extension SessionAuthenticator {
    enum Error: Swift.Error {
        case primaryAccountNotFound
    }
}

// MARK: - AuthenticationState -

extension SessionAuthenticator {
    enum BiometricState {
        case disabled
        case notVerified
        case verified
        
        var isPermitted: Bool {
            switch self {
            case .disabled, .verified:
                return true
            case .notVerified:
                return false
            }
        }
    }
    
    enum AuthenticationState {
        case loggedOut
        case migrating
        case pending
        case loggedIn(Session)
        
        var intValue: Int {
            switch self {
            case .loggedOut: return 0
            case .migrating: return 1
            case .pending:   return 2
            case .loggedIn:  return 3
            }
        }
    }
}

// MARK: - InitializedAccount -

struct InitializedAccount {
    
    let keyAccount: KeyAccount
    let owner: AccountCluster
    let userID: UserID
    
    fileprivate init(keyAccount: KeyAccount, userID: UserID) {
        self.keyAccount = keyAccount
        self.owner = .init(authority: .derive(using: .primary(), mnemonic: keyAccount.mnemonic))
        self.userID = userID
    }
}

// MARK: - Mock -

extension SessionAuthenticator {
    static let mockCameraSession = CameraSession<CodeExtractor>()
    
    static let mock: SessionAuthenticator = SessionAuthenticator(container: .mock)
}
