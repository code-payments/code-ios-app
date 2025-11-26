//
//  SessionAuthenticator.swift
//  Code
//
//  Created by Dima Bart on 2021-11-04.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@MainActor
final class SessionAuthenticator: ObservableObject {

    let accountManager: AccountManager

    @Published private(set) var loginButtonState: ButtonState = .normal
    @Published private(set) var isUnlocked: Bool = false
    @Published private(set) var state: AuthenticationState = .migrating
    @Published private(set) var unauthenticatedUserFlags: UnauthenticatedUserFlags?

    var isLoggedIn: Bool {
        if case .loggedIn = state {
            return true
        } else {
            return false
        }
    }

    var requiresUpgrade: Bool {
        guard let minBuildNumber = unauthenticatedUserFlags?.minBuildNumber, minBuildNumber > 0 else {
            return false // No minimum requirement or server didn't provide one
        }

        guard let currentBuild = UInt32(AppMeta.build) else {
            return false // Can't parse build number, default to allowing access
        }

        return currentBuild < minBuildNumber
    }

    private let container: Container
    private let client: Client
    private let flipClient: FlipClient
    private var poller: Poller?
    
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

        // Start polling for unauthenticated user flags
        startPollingUnauthenticatedUserFlags()

        initializeState { userAccount in
            let initializedAccount = InitializedAccount(
                keyAccount: userAccount.keyAccount,
                userID: userAccount.userID
            )

            self.completeLogin(with: initializedAccount)
        } didFindRecentAccount: { [weak self] keyAccount in
            Task {
                if let account = try await self?.initialize(using: keyAccount.mnemonic, isRegistration: false) {
                    self?.completeLogin(with: account)
                    Analytics.autoLoginComplete()
                }
            }
        }
    }
    
    private func initializeState(count: Int = 0, didAuthenticate: @escaping (UserAccount) -> Void, didFindRecentAccount: @escaping (KeyAccount) -> Void) {
        trace(.warning)
        
        let userAccount = accountManager.fetchCurrentUserAccount()
        if let userAccount = userAccount {
            didAuthenticate(userAccount)
            
            // Inserting a new version of this key account
            // will update the `lastSeen` date and the
            // device name that is currently using it.
            accountManager.upsert(keyAccount: userAccount.keyAccount)
            
        } else {
            
            if let recentAccount = accountManager.fetchHistorical(sortBy: .lastSeen).first {
                didFindRecentAccount(recentAccount.account)
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
                                didAuthenticate: didAuthenticate,
                                didFindRecentAccount: didFindRecentAccount
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
    
    // MARK: - Unauthenticated User Flags Polling -

    private func startPollingUnauthenticatedUserFlags() {
        poller = Poller(seconds: 30, fireImmediately: true) { [weak self] in
            Task {
                await self?.fetchUnauthenticatedUserFlags()
            }
        }
    }

    private func fetchUnauthenticatedUserFlags() async {
        do {
            let flags = try await flipClient.fetchUnauthenticatedUserFlags()
            self.unauthenticatedUserFlags = flags
            trace(.success, components: "Fetched unauthenticated user flags")
        } catch {
            trace(.failure, components: "Failed to fetch unauthenticated user flags: \(error)")
        }
    }

    // MARK: - Session -

    private func createSessionContainer(container: Container, initializedAccount: InitializedAccount) -> SessionContainer {
        let owner = initializedAccount.owner
        let ownerPublicKey = owner.authority.keyPair.publicKey
        
        let database = try! initializeDatabase(owner: ownerPublicKey)
        
        let historyController = HistoryController(
            container: container,
            database: database,
            owner: owner
        )
        
        let ratesController = RatesController(
            container: container,
            database: database
        )
        
        let pushController = PushController(
            owner: owner.authority.keyPair,
            client: container.flipClient
        )
        
        let tokenController = TokenController(
            container: container,
            database: database,
        )
        
        let session = Session(
            container: container,
            historyController: historyController,
            ratesController: ratesController,
            tokenController: tokenController,
            database: database,
            keyAccount: initializedAccount.keyAccount,
            owner: owner,
            userID: initializedAccount.userID
        )
        
        let poolController = PoolController(
            container: container,
            session: session,
            ratesController: ratesController,
            keyAccount: initializedAccount.keyAccount,
            owner: owner,
            userID: initializedAccount.userID,
            database: database
        )
        
        let poolViewModel = PoolViewModel(
            container: container,
            session: session,
            ratesController: ratesController,
            poolController: poolController
        )
        
        let onrampViewModel = OnrampViewModel(
            container: container,
            session: session,
            ratesController: ratesController
        )
        
        let walletConnection = WalletConnection(owner: owner)
        
        return SessionContainer(
            session: session,
            database: database,
            walletConnection: walletConnection,
            ratesController: ratesController,
            historyController: historyController,
            tokenController: tokenController,
            pushController: pushController,
            poolController: poolController,
            poolViewModel: poolViewModel,
            onrampViewModel: onrampViewModel
        )
    }
    
    // MARK: - Database -
    
    private func initializeDatabase(owner: PublicKey) throws -> Database {
        try createApplicationSupportIfNeeded()
        
        // Currently we don't do migrations so every time
        // the user version is outdated, we'll rebuild the
        // database during sync.
        let userVersion = (try? Database.userVersion(owner: owner)) ?? 0
        let currentVersion = try InfoPlist.value(for: "SQLiteVersion").integer()
        if currentVersion > userVersion {
            try Database.deleteStore(owner: owner)
            trace(.failure, components: "Outdated user version, deleted database.")
            try Database.setUserVersion(version: currentVersion, owner: owner)
        }
        
        return try Database(url: .dataStore(owner: owner))
    }
    
    private func createApplicationSupportIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: URL.applicationSupportDirectory.path) {
            try FileManager.default.createDirectory(
                at: .applicationSupportDirectory,
                withIntermediateDirectories: false
            )
        }
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
        
        let cluster = AccountCluster(
            authority: derivedKey,
            mint: .usdc, // Initial account is always USDC
            timeAuthority: .usdcAuthority
        )
        
        do {
            let userID: UserID
            
            // Create VM accounts first, this is a no-op
            // if the accounts have been previously created
            try await client.createAccounts(
                owner: cluster.authority.keyPair,
                mint: .usdc, // USDC is the foundation mint
                cluster: cluster,
                kind: .primary,
                derivationIndex: 0
            )
            
            if isRegistration {
                userID = try await flipClient.register(owner: keyAccount.owner)
            } else {
                userID = try await flipClient.login(owner: keyAccount.owner)
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
        
        Analytics.setIdentity(initializedAccount.userID)
    }
    
    func switchAccount(to mnemonic: MnemonicPhrase) {
        Task {
            loginButtonState = .loading
            // State is changed back to .normal
            // within initialize()
            
            logout()
            try await Task.delay(seconds: 1)
        
            completeLogin(
                with: try await initialize(
                    using: mnemonic,
                    isRegistration: false
                )
            )
        }
    }
    
    func deleteAndLogout() {
        if case .loggedIn(let container) = state {
            accountManager.setDeleted(
                ownerPublicKey: container.session.owner.authorityPublicKey,
                deleted: true
            )
            logout()
        }
    }
    
    func logout() {
        if case .loggedIn(let container) = state {
            container.session.prepareForLogout()
            container.pushController.prepareForLogout()
            container.tokenController.prepareForLogout()
        }
        
        accountManager.resetForLogout()
        
        state = .loggedOut
        UserDefaults.wasLoggedIn = false
        
        trace(.note, components: "Logged out")
    }
}

// MARK: - SessionContainer -

struct SessionContainer {
    
    let session: Session
    let database: Database
    let walletConnection: WalletConnection
    let ratesController: RatesController
    let historyController: HistoryController
    let tokenController: TokenController
    let pushController: PushController
    let poolController: PoolController
    let poolViewModel: PoolViewModel
    let onrampViewModel: OnrampViewModel
    
    fileprivate func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environmentObject(session)
            .environmentObject(walletConnection)
            .environmentObject(ratesController)
            .environmentObject(historyController)
            .environmentObject(pushController)
            .environmentObject(tokenController)
    }
    
    @MainActor
    static let mock: SessionContainer = .init(session: .mock, database: .mock, walletConnection: .mock, ratesController: .mock, historyController: .mock, tokenController: .mock, pushController: .mock, poolController: .mock, poolViewModel: .mock, onrampViewModel: .mock)
}

extension View {
    func injectingEnvironment(from sessionContainer: SessionContainer) -> some View {
        sessionContainer.injectingEnvironment(into: self)
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
        case loggedIn(SessionContainer)
        
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
        self.owner = .init(
            authority: .derive(using: .primary(), mnemonic: keyAccount.mnemonic),
            mint: .usdc, // Initial account is always USDC
            timeAuthority: .usdcAuthority
        )
        self.userID = userID
    }
}

// MARK: - Mock -

extension SessionAuthenticator {
    static let mockCameraSession = CameraSession<CodeExtractor>()
    
    static let mock: SessionAuthenticator = SessionAuthenticator(container: .mock)
}
