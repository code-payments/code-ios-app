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

private extension Keychain {
    
    @SecureCodable(.restricted)
    static var isRestricted: Bool?
    
    static func resetRestricted() {
        isRestricted = nil
    }
}

@MainActor
final class SessionAuthenticator: ObservableObject {
    
    let accountManager: AccountManager
    
    @Published private(set) var inProgress: Bool = false
    @Published private(set) var isRestricted: Bool = false
    @Published private(set) var isUnlocked: Bool = false
    @Published private(set) var state: AuthenticationState = .migrating
    
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
    
    private var cancellables: Set<AnyCancellable> = []
    
    @Defaults(.launchCount) private static var launchCount: Int?
    
    // MARK: - Init -
    
    init(client: Client, exchange: Exchange, cameraSession: CameraSession<CodeExtractor>, bannerController: BannerController, reachability: Reachability, betaFlags: BetaFlags, abacus: Abacus) {
        self.client = client
        self.exchange = exchange
        self.cameraSession = cameraSession
        self.bannerController = bannerController
        self.reachability = reachability
        self.betaFlags = betaFlags
        self.abacus = abacus
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
        }
        
        validateInvitationStatus()
    }
    
    // MARK: - Session -
    
    private func createSessionContainer(keyAccount: KeyAccount, user: User, client: Client, exchange: Exchange, cameraSession: CameraSession<CodeExtractor>, bannerController: BannerController, reachability: Reachability, betaFlags: BetaFlags) -> SessionContainer {
        
        let historyController = HistoryController(client: client, owner: keyAccount.owner)
        
        let session = Session(
            organizer: Organizer(mnemonic: keyAccount.mnemonic),
            user: user,
            client: client,
            exchange: exchange,
            cameraSession: cameraSession,
            bannerController: bannerController,
            reachability: reachability,
            betaFlags: betaFlags,
            abacus: abacus,
            historyController: historyController
        )
        
        session.delegate = self
        
        let contactsController = ContactsController(client: client, user: user, owner: keyAccount.owner)
        
        return SessionContainer(
            session: session,
            inviteController: InviteController(client: client, user: user),
            historyController: historyController,
            contactsController: contactsController
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
                // TODO: Can return legacy account, will need to perform a migration
                
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
    
    private func setRestricted(_ restricted: Bool) {
        Keychain.isRestricted = restricted
        isRestricted = restricted
    }
    
    func deleteAndLogout() {
        if case .loggedIn(let container) = state {
            accountManager.delete(ownerPublicKey: container.session.organizer.ownerKeyPair.publicKey)
            logout()
        }
    }
    
    func logout() {
        accountManager.resetForLogout()
        Keychain.resetRestricted()
        
        state = .loggedOut
        isRestricted = false
        
        trace(.note, components: "Logged out")
    }
    
    // MARK: - Authenticate -
    
    func validateInvitationStatus() {
        let (_, user) = accountManager.fetchCurrent()
        
        guard let user = user else {
            trace(.warning, components: "Failed to validate invitation status. No user stored in key chain.")
            return
        }
        
        Task {
            do {
                let status = try await client.fetchInviteStatus(userID: user.id)
                setRestricted(status == .revoked)
            } catch {
                // There's not enough information here to make a call
                // on restricting access. The request could've failed
                // as a result of poor network connection, etc.
            }
        }
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
    let inviteController: InviteController
    let historyController: HistoryController
    let contactsController: ContactsController
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
        abacus: .mock
    )
}

extension SessionContainer {
    static let mock = SessionContainer(
        session: .mock,
        inviteController: .mock,
        historyController: .mock,
        contactsController: .mock
    )
}
