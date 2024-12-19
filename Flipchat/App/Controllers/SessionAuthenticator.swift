//
//  SessionAuthenticator.swift
//  Code
//
//  Created by Dima Bart on 2021-11-04.
//

import Foundation
import Combine
import FlipchatServices
import CodeUI

@MainActor
extension UserDefaults {
    
    @Defaults(.launchCount) 
    fileprivate static var launchCount: Int?
    
    @Defaults(.wasLoggedIn)
    fileprivate static var wasLoggedIn: Bool?
}

@MainActor
final class SessionAuthenticator: ObservableObject {
    
    let accountManager: AccountManager
    
    @Published private(set) var loginState: ButtonState = .normal
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
    
    private(set) lazy var containerViewModel = ContainerViewModel(sessionAuthenticator: self)
    
    private let flipClient: FlipchatClient
    private let client: Client
    private let exchange: Exchange
    private let banners: Banners
    private let betaFlags: BetaFlags
    private let biometrics: Biometrics
    
    private var biometricsQueue: [ThrowingAction] = []
    
    weak var container: AppContainer!
    
    // MARK: - Init -
    
    init(container: AppContainer) {
        self.container      = container
        self.flipClient     = container.flipClient
        self.client         = container.client
        self.exchange       = container.exchange
        self.banners        = container.banners
        self.betaFlags      = container.betaFlags
        self.biometrics     = container.biometrics
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
                    self.completeLogin(with: try await self.initialize(using: mnemonic, name: nil, isRegistration: false))
                } catch {
                    Analytics.userMigrationFailed()
                    self.state = .loggedOut
                }
            }
            
        } didAuthenticate: { keyAccount, userID, userFlags in
            self.completeLogin(with: InitializedAccount(keyAccount: keyAccount, userID: userID, userFlags: userFlags))
        }
        
        updateBiometricsState()
    }
    
    private func initializeState(count: Int = 0, migration: @escaping (MnemonicPhrase) -> Void, didAuthenticate: @escaping (KeyAccount, UserID, UserFlags) -> Void) {
        trace(.warning)
        
        // The most important Keychain item is the key account
        // because it's the only thing we can't derive. If the
        // the user is missing we'll transition into a 'migration'
        // and fetch the latest user data from the server.
        let (keyAccount, userID, userFlags) = accountManager.fetchCurrent()
        
        if let keyAccount = keyAccount {
            if let userID, let userFlags {
                didAuthenticate(keyAccount, userID, userFlags)
                
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
    
    private func createSessionContainer(keyAccount: KeyAccount, userID: UserID, userFlags: UserFlags) -> AuthenticatedState {
        let organizer = Organizer(mnemonic: keyAccount.mnemonic)
        let session = Session(
            userID: userID,
            userFlags: userFlags,
            organizer: organizer,
            client: client,
            flipClient: flipClient,
            exchange: exchange,
            banners: banners,
            betaFlags: betaFlags
        )
        
        let chatController = ChatController(
            session: session,
            client: flipClient,
            paymentClient: client,
            organizer: organizer
        )
        
        let chatViewModel = ChatViewModel(
            session: session,
            chatController: chatController,
            client: flipClient,
            exchange: exchange,
            banners: banners,
            containerViewModel: containerViewModel
        )
        
        let pushController = PushController(
            owner: organizer.ownerKeyPair,
            client: flipClient
        )
        
        let storeController = StoreController(client: flipClient, owner: organizer.ownerKeyPair)
        
        let state = AuthenticatedState(
            session: session,
            chatController: chatController,
            chatViewModel: chatViewModel,
            containerViewModel: containerViewModel,
            pushController: pushController,
            storeController: storeController
        )
        
        initializeSession(state: state)
        
        session.delegate = self
        
        return state
    }
    
    private func initializeSession(state: AuthenticatedState) {
        let owner = state.session.organizer.ownerKeyPair
        Task {
            // 1. Push permissions
            async let _ = try state.pushController.authorizeAndRegister()
            
            // 2. Update user flags
            let flags = try await state.session.updateUserFlags()
            
            trace(.success, components:
                  "Updated user flags",
                  "Staff: \(flags.isStaff ? "yes" : "no")",
                  "Registered: \(flags.isRegistered ? "yes" : "no")"
            )
        }
    }
    
    // MARK: - Login -
    
    func initialize(using mnemonic: MnemonicPhrase, name: String?, isRegistration: Bool) async throws -> InitializedAccount {
        loginState = .loading
        
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
            // 1. Open all required VM accounts
            try await client.createAccounts(with: organizer)
            
            // 2. If a name is provided, we'll register a new
            // account but if it's ommited, we'll attempt a login
            let userID: UserID
            let userFlags: UserFlags
            
            if isRegistration {
                userID = try await flipClient.register(name: name, owner: owner)
                userFlags = try await flipClient.fetchUserFlags(userID: userID, owner: owner)
                
                // 3. For new users only, airdrop initial balance
                //_ = try await client.airdrop(type: .getFirstKin, owner: organizer.ownerKeyPair)
                
            } else {
                userID = try await flipClient.login(owner: owner)
                userFlags = try await flipClient.fetchUserFlags(userID: userID, owner: owner)
            }
            
            accountManager.set(
                account: keyAccount,
                userID: userID,
                userFlags: userFlags
            )
            
            trace(.note, components: "Owner: \(organizer.ownerKeyPair.publicKey)")
            
            return InitializedAccount(
                keyAccount: keyAccount,
                userID: userID,
                userFlags: userFlags
            )
            
        } catch {
            ErrorReporting.captureError(error)
            loginState = .normal
            throw error
        }
    }
    
    func completeLogin(with initializedAccount: InitializedAccount) {
        Task {
            loginState = .success
            try await Task.delay(milliseconds: 500)
            loginState = .normal
        }
        
        trace(.note, components:
            "Owner: \(initializedAccount.keyAccount.ownerPublicKey)"
        )
        
        let container = createSessionContainer(
            keyAccount: initializedAccount.keyAccount,
            userID: initializedAccount.userID,
            userFlags: initializedAccount.userFlags
        )
        
        state = .loggedIn(container)
        UserDefaults.wasLoggedIn = true
        
        Analytics.setIdentity(initializedAccount.userID)
    }
    
    func deleteAndLogout() {
        if case .loggedIn(let state) = state {
            accountManager.delete(ownerPublicKey: state.session.organizer.ownerKeyPair.publicKey)
            logout()
        }
    }
    
    func logout() {
        let preState = state
        
        accountManager.resetForLogout()
        
        state = .loggedOut
        
        if case .loggedIn(let state) = preState {
            state.session.prepareForLogout()
            state.chatController.prepareForLogout()
            state.pushController.prepareForLogout()
        }
        
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
    
    func didUpdateUserFlags(flags: UserFlags) {
        accountManager.update(userFlags: flags)
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
    
    enum AuthenticationState: Equatable {
        
        case loggedOut
        case migrating
        case pending
        case loggedIn(AuthenticatedState)
        
        static func == (lhs: SessionAuthenticator.AuthenticationState, rhs: SessionAuthenticator.AuthenticationState) -> Bool {
            switch (lhs, rhs) {
            case (.loggedOut, .loggedOut):
                return true
            case (.migrating, .migrating):
                return true
            case (.pending, .pending):
                return true
            case (.loggedIn, .loggedIn):
                return true
            default:
                return false
            }
        }
    }
}

struct AuthenticatedState {
    let session: Session
    let chatController: ChatController
    let chatViewModel: ChatViewModel
    let containerViewModel: ContainerViewModel
    let pushController: PushController
    let storeController: StoreController
}

// MARK: - InitializedAccount -

struct InitializedAccount {
    
    let keyAccount: KeyAccount
    let userID: UserID
    let userFlags: UserFlags
    
    fileprivate init(keyAccount: KeyAccount, userID: UserID, userFlags: UserFlags) {
        self.keyAccount = keyAccount
        self.userID = userID
        self.userFlags = userFlags
    }
}

// MARK: - Mock -

extension SessionAuthenticator {
    static let mock: SessionAuthenticator = SessionAuthenticator(container: .mock)
}

extension AuthenticatedState {
    @MainActor
    static let mock: AuthenticatedState = AuthenticatedState(
        session: .mock,
        chatController: .mock,
        chatViewModel: .mock,
        containerViewModel: .mock,
        pushController: .mock,
        storeController: .mock
    )
}
