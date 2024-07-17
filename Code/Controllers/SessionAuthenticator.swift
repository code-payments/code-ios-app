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
    
    @Defaults(.launchCount) private static var launchCount: Int?
    
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
        if Self.launchCount == nil {
            trace(.note, components: "First launch...")
        }
        
        Self.launchCount = (Self.launchCount ?? 0) + 1
        trace(.note, components: "Launch count: \(Self.launchCount!)")
        
        let performMigration: (MnemonicPhrase) -> Void = { seedPhrase in
            Task {
                do {
                    self.completeLogin(with: try await self.initialize(using: seedPhrase))
                } catch {
                    Analytics.userMigrationFailed()
                    self.state = .loggedOut
                }
            }
        }
        
        // The most important Keychain item is the key account
        // because it's the only thing we can't derive. If the
        // the user is missing we'll transition into a 'migration'
        // and fetch the latest user data from the server.
        let (keyAccount, user) = accountManager.fetchCurrent()
        
        if let keyAccount = keyAccount {
            if let user = user {
                completeLogin(with: InitializedAccount(keyAccount: keyAccount, user: user))
                
            } else {
                state = .migrating
                performMigration(keyAccount.mnemonic)
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
            }
            
            // It's possible the keychain credentials
            // rely on being loaded from iCloud and can
            // be delayed. We'll check after some time
            // to see if the state has changed.
            Task {
                try await Task.delay(seconds: 5)
                
                let (keyAccount, user) = accountManager.fetchCurrent()
                if keyAccount != nil || user != user {
                    // If the a keyaccount or user exists at this point
                    // it means that something went wrong in the initial
                    // query so the user "appears" logged out.
                    Analytics.unintentialLogout()
                }
            }
        }
        
        updateBiometricsState()
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
        
        Analytics.setIdentity(initializedAccount.user)
    }
    
    func deleteAndLogout() {
        if case .loggedIn(let container) = state {
            accountManager.delete(ownerPublicKey: container.session.organizer.ownerKeyPair.publicKey)
            logout()
        }
    }
    
    func logout() {
        accountManager.resetForLogout()
        
        state = .loggedOut
        
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
