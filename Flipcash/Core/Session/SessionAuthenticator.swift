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
    
    @Published private(set) var inProgress: Bool = false
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
    
    // MARK: - Init -
    
    init(container: Container) {
        self.container      = container
        self.client         = container.client
        self.accountManager = container.accountManager
        
        // Update launch state.
        // This is a fresh install.
        if UserDefaults.launchCount == nil {
            trace(.note, components: "First launch...")
        }
        
        UserDefaults.launchCount = (UserDefaults.launchCount ?? 0) + 1
        trace(.note, components: "Launch count: \(UserDefaults.launchCount!)")
        
        initializeState { mnemonic in // Migration
            Task {
                do {
                    self.completeLogin(with: try await self.initialize(using: mnemonic))
                } catch {
//                    Analytics.userMigrationFailed()
                    self.state = .loggedOut
                }
            }
            
        } didAuthenticate: { keyAccount, user in
            self.completeLogin(with: InitializedAccount(keyAccount: keyAccount, user: user))
        }
    }
    
    private func initializeState(count: Int = 0, migration: @escaping (MnemonicPhrase) -> Void, didAuthenticate: @escaping (KeyAccount, User) -> Void) {
        trace(.warning)
        
        // The most important Keychain item is the key account
        // because it's the only thing we can't derive. If the
        // the user is missing we'll transition into a 'migration'
        // and fetch the latest user data from the server.
        let (keyAccount, user) = accountManager.fetchCurrent()
        
        if let keyAccount = keyAccount {
            if let user = user {
                didAuthenticate(keyAccount, user)
                
                if count > 0 {
                    trace(.failure, components: "Logged in after \(count) retries")
                    Task {
                        // Mixpanel isn't initialized yet
                        try await Task.delay(seconds: 1)
//                        Analytics.loginByRetry(count: count)
                    }
                }
                
            } else {
                state = .migrating
                migration(keyAccount.mnemonic)
            }
            
            // Inserting a new version of this key account
            // will update the `lastSeen` date and the
            // device name that is currently using it.
            accountManager.upsert(account: keyAccount)
            
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
                                migration: migration,
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
            user: initializedAccount.user
        )
        
//        session.delegate = self
        
        return session
    }
    
    // MARK: - Login -
    
    func initialize(using mnemonic: MnemonicPhrase) async throws -> InitializedAccount {
        inProgress = true
        defer {
            inProgress = false
        }
        
//        let owner      = mnemonic.solanaKeyPair()
//        let organizer  = Organizer(mnemonic: mnemonic)
//        let keyAccount = KeyAccount(
//            mnemonic: mnemonic,
//            derivedKey: DerivedKey(
//                path: .solana,
//                keyPair: owner
//            )
//        )
//        
//        do {
//            let phoneLink = try await client.fetchAssociatedPhoneNumber(owner: owner)
//            let user      = try await client.fetchUser(phone: phoneLink.phone, owner: owner)
//            
//            // Check if this is an existing account that will only
//            // need login or a brand new account that requires
//            // creation before it can be used
//            do {
//                let accounts = try await client.fetchAccountInfos(owner: owner)
//                
//                // If primary vault exists, it's an existing user
//                guard accounts[organizer.primaryVault] != nil else {
//                    throw Error.primaryAccountNotFound
//                }
//                
//            } catch ErrorFetchAccountInfos.notFound {
//                try await client.createAccounts(with: organizer)
//                
//            }
//            
//            accountManager.set(
//                account: keyAccount,
//                user: user
//            )
//            
//            trace(.note, components: "Owner: \(organizer.ownerKeyPair.publicKey)")
//            
//            return InitializedAccount(
//                keyAccount: keyAccount,
//                user: user
//            )
//            
//        } catch {
////            ErrorReporting.captureError(error)
//            throw error
//        }
        
        return InitializedAccount(
            keyAccount: .init(
                mnemonic: mnemonic,
                derivedKey: .derive(
                    using: .solana,
                    mnemonic: mnemonic
                )
            ),
            user: .mock
        )
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
    }
}

// MARK: - InitializedAccount -

struct InitializedAccount {
    
    let keyAccount: KeyAccount
    let owner: AccountCluster
    let user: User
    
    fileprivate init(keyAccount: KeyAccount, user: User) {
        self.keyAccount = keyAccount
        self.owner = .init(authority: .derive(using: .primary(), mnemonic: keyAccount.mnemonic))
        self.user = user
    }
}

// MARK: - Mock -

extension SessionAuthenticator {
    static let mockCameraSession = CameraSession<CodeExtractor>()
    
    static let mock: SessionAuthenticator = SessionAuthenticator(container: .mock)
}
