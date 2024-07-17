//
//  SessionAuthenticator.swift
//  Code
//
//  Created by Dima Bart on 2021-11-04.
//

import Foundation
import Combine
import CodeServices
import CodeUI

extension UserDefaults {
    
    @Defaults(.launchCount) 
    fileprivate static var launchCount: Int?
    
    @Defaults(.wasLoggedIn)
    fileprivate static var wasLoggedIn: Bool?
}

@MainActor
final class SessionAuthenticator: ObservableObject {
    
    let accountManager: AccountManager
    
    @Published private(set) var inProgress: Bool = false
    @Published private(set) var isUnlocked: Bool = false
    @Published private(set) var state: AuthenticationState = .migrating
    @Published private(set) var biometricState: BiometricState = .disabled
    
    private(set) var biometricsRequireReverification: Bool = true
    
    var isLoggedIn: Bool {
        if case .loggedIn = state {
            return true
        } else {
            return false
        }
    }
    
    private let client: Client
    private let exchange: Exchange
    private let cameraSession: CameraSession<CodeExtractor>
    private let bannerController: BannerController
    private let reachability: Reachability
    private let betaFlags: BetaFlags
    private let abacus: Abacus
    private let biometrics: Biometrics
    
    private var biometricsQueue: [ThrowingAction] = []
    
    // MARK: - Init -
    
    init(client: Client, exchange: Exchange, cameraSession: CameraSession<CodeExtractor>, bannerController: BannerController, reachability: Reachability, betaFlags: BetaFlags, abacus: Abacus, biometrics: Biometrics) {
        self.client = client
        self.exchange = exchange
        self.cameraSession = cameraSession
        self.bannerController = bannerController
        self.reachability = reachability
        self.betaFlags = betaFlags
        self.abacus = abacus
        self.biometrics = biometrics
        self.accountManager = AccountManager()
        
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
                    Analytics.userMigrationFailed()
                    self.state = .loggedOut
                }
            }
            
        } didAuthenticate: { keyAccount, user in
            self.completeLogin(with: InitializedAccount(keyAccount: keyAccount, user: user))
        }
        
        updateBiometricsState()
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
                        Analytics.loginByRetry(count: count)
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
                            
                            ErrorReporting.breadcrumb(
                                name: "Retrying login",
                                metadata: ["count": "\(nextCount)"],
                                type: .process
                            )
                        }
                        
                    } else {
                        Analytics.unintentialLogout()
                    }
                }
            }
        }
    }
    
    // MARK: - Biometrics -
    
    func invalidateBiometrics() {
        biometricsRequireReverification = true
    }
    
    func updateBiometricsState() {
        if biometrics.isEnabled {
            if biometricsRequireReverification {
                biometricState = .notVerified
            }
        } else {
            biometricState = .disabled
        }
    }
    
    func verifyBiometrics() async -> Bool {
        guard let context = biometrics.verificationContext() else {
            return false
        }
        
        let isVerified = await context.verify(reason: .general)
        if isVerified {
            biometricState = .verified
            Task {
                await flushBiometricsQueue()
            }
        } else {
            // Leave unchanged
        }
        
        return isVerified
    }
    
    func enqueueAfterBiometrics(action: @escaping ThrowingAction) {
        if biometricState.isPermitted {
            Task {
                try await action()
            }
        } else {
            biometricsQueue.append(action)
        }
    }
    
    func flushBiometricsQueue() async {
        while !biometricsQueue.isEmpty {
            let action = biometricsQueue.removeFirst()
            do {
                try await action()
            } catch {}
        }
    }
    
    // MARK: - Session -
    
    private func createSessionContainer(keyAccount: KeyAccount, user: User, client: Client, exchange: Exchange, cameraSession: CameraSession<CodeExtractor>, bannerController: BannerController, reachability: Reachability, betaFlags: BetaFlags) -> SessionContainer {
        
        let organizer = Organizer(mnemonic: keyAccount.mnemonic)
        
        let chatController = ChatController(client: client, organizer: organizer)
        
        let session = Session(
            organizer: organizer,
            user: user,
            client: client,
            exchange: exchange,
            cameraSession: cameraSession,
            bannerController: bannerController,
            reachability: reachability,
            betaFlags: betaFlags,
            abacus: abacus,
            chatController: chatController
        )
        
        session.delegate = self
        
        return SessionContainer(
            session: session,
            chatController: chatController
        )
    }
    
    // MARK: - Login -
    
    func initialize(using mnemonic: MnemonicPhrase) async throws -> InitializedAccount {
        inProgress = true
        defer {
            inProgress = false
        }
        
        let owner      = mnemonic.solanaKeyPair()
        let organizer  = Organizer(mnemonic: mnemonic)
        let keyAccount = KeyAccount(
            mnemonic: mnemonic,
            derivedKey: DerivedKey(
                path: .solana,
                keyPair: owner
            )
        )
        
        do {
            let phoneLink = try await client.fetchAssociatedPhoneNumber(owner: owner)
            let user      = try await client.fetchUser(phone: phoneLink.phone, owner: owner)
            
            // Check if this is an existing account that will only
            // need login or a brand new account that requires
            // creation before it can be used
            do {
                let accounts = try await client.fetchAccountInfos(owner: owner)
                
                // If primary vault exists, it's an existing user
                guard accounts[organizer.primaryVault] != nil else {
                    throw Error.primaryAccountNotFound
                }
                
            } catch ErrorFetchAccountInfos.notFound {
                try await client.createAccounts(with: organizer)
                
            } catch ErrorFetchAccountInfos.migrationRequired {
                // Do nothing, account will be migrated on subsequent balance fetch after login
            }
            
            accountManager.set(
                account: keyAccount,
                user: user
            )
            
            trace(.note, components: "Owner: \(organizer.ownerKeyPair.publicKey)")
            
            return InitializedAccount(
                keyAccount: keyAccount,
                user: user
            )
            
        } catch {
            ErrorReporting.captureError(error)
            throw error
        }
    }
    
    func completeLogin(with initializedAccount: InitializedAccount) {
        trace(.note, components:
            "Owner: \(initializedAccount.keyAccount.ownerPublicKey)"
        )
        
        let container = createSessionContainer(
            keyAccount: initializedAccount.keyAccount,
            user: initializedAccount.user,
            client: client,
            exchange: exchange,
            cameraSession: cameraSession,
            bannerController: bannerController,
            reachability: reachability,
            betaFlags: betaFlags
        )
        
        state = .loggedIn(container)
        UserDefaults.wasLoggedIn = true
        
        Analytics.setIdentity(initializedAccount.user)
    }
    
    func deleteAndLogout() {
        if case .loggedIn(let container) = state {
            accountManager.delete(ownerPublicKey: container.session.organizer.ownerKeyPair.publicKey)
            logout()
        }
    }
    
    func logout() {
        if case .loggedIn(let container) = state {
            container.session.prepareForLogout()
        }
        
        accountManager.resetForLogout()
        
        state = .loggedOut
        UserDefaults.wasLoggedIn = false
        
        trace(.note, components: "Logged out")
    }
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
        case loggedIn(SessionContainer)
    }
}

// MARK: - SessionContainer -

struct SessionContainer {
    let session: Session
    let chatController: ChatController
}

// MARK: - InitializedAccount -

struct InitializedAccount {
    
    let keyAccount: KeyAccount
    let user: User
    
    fileprivate init(keyAccount: KeyAccount, user: User) {
        self.keyAccount = keyAccount
        self.user = user
    }
}

// MARK: - Mock -

extension SessionAuthenticator {
    static let mockCameraSession = CameraSession<CodeExtractor>()
    
    static let mock: SessionAuthenticator = SessionAuthenticator(
        client: .mock,
        exchange: .mock,
        cameraSession: mockCameraSession,
        bannerController: .mock,
        reachability: .mock,
        betaFlags: .mock,
        abacus: .mock,
        biometrics: .mock
    )
}

extension SessionContainer {
    
    @MainActor
    static let mock = SessionContainer(
        session: .mock,
        chatController: .mock
    )
}
