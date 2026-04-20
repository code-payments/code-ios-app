//
//  SessionAuthenticator.swift
//  Flipcash
//
//  Created by Dima Bart on 2021-11-04.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.session-auth")

/// Manages authentication state, login flow, and session lifecycle.
///
/// Handles account creation, login, logout, and session migration.
/// Publishes the current ``AuthenticationState`` which drives the
/// top-level view hierarchy (intro → login → scan screen).
///
/// Inject via `@Environment(SessionAuthenticator.self)`.
@MainActor @Observable
final class SessionAuthenticator {

    @ObservationIgnored let accountManager: AccountManager

    /// Current state of the login button (normal, loading, disabled).
    private(set) var loginButtonState: ButtonState = .normal

    /// Whether the user has been unlocked (biometrics/passcode verified).
    private(set) var isUnlocked: Bool = false

    /// The top-level authentication state driving the view hierarchy.
    private(set) var state: AuthenticationState = .migrating

    /// Feature flags available before authentication (e.g. minimum build version).
    private(set) var unauthenticatedUserFlags: UnauthenticatedUserFlags?

    /// Whether any of the user's primary accounts has left the `locked`
    /// state, meaning the Access Key can no longer be used in Flipcash.
    /// Drives ``ForceLogoutScreen`` display. One-way latch for the lifetime
    /// of the login — reset on ``logout()``.
    private(set) var requiresForceLogout: Bool = false

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

    @ObservationIgnored private let container: Container
    @ObservationIgnored private let client: Client
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private var poller: Poller?
    
    // MARK: - Init -
    
    init(container: Container) {
        self.container      = container
        self.client         = container.client
        self.flipClient     = container.flipClient
        self.accountManager = container.accountManager

        // Update launch state.
        // This is a fresh install.
        if UserDefaults.launchCount == nil {
            logger.debug("First launch...")
        }

        UserDefaults.launchCount = (UserDefaults.launchCount ?? 0) + 1
        logger.debug("Launch count", metadata: ["count": "\(UserDefaults.launchCount!)"])

        // Poll server-driven gates that can block app use
        // (forced upgrade, forced logout on timelock unlock).
        startPolling()

        // During UI testing the deeplink handles login. Skip auto-login
        // to avoid racing with resetForUITesting() and the deeplink's
        // switchAccount(to:) call.
        guard !CommandLine.arguments.contains("--ui-testing") else {
            accountManager.nukeForUITesting()
            state = .loggedOut
            return
        }

        initializeState { userAccount in
            let initializedAccount = InitializedAccount(
                keyAccount: userAccount.keyAccount,
                userID: userAccount.userID
            )

            self.completeLogin(with: initializedAccount)
        } didFindRecentAccount: { [weak self] keyAccount in
            Task {
                do {
                    if let account = try await self?.initialize(using: keyAccount.mnemonic, isRegistration: false) {
                        self?.completeLogin(with: account)
                        Analytics.track(event: Analytics.GeneralEvent.autoLoginComplete)
                    }
                } catch {
                    self?.logout()
                }
            }
        }
    }
    
    private func initializeState(count: Int = 0, didAuthenticate: @escaping (UserAccount) -> Void, didFindRecentAccount: @escaping (KeyAccount) -> Void) {
        logger.debug("initializeState called")
        
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
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Polling -

    /// Polls server-driven state that gates app use. Fires immediately and
    /// then every 30s for the lifetime of the authenticator, covering both
    /// ``requiresUpgrade`` (always) and ``requiresForceLogout`` (once
    /// logged in).
    private func startPolling() {
        poller = Poller(seconds: 30, fireImmediately: true) { [weak self] in
            Task {
                await self?.fetchUnauthenticatedUserFlags()
                await self?.checkForUnusableAccount()
            }
        }
    }

    private func fetchUnauthenticatedUserFlags() async {
        do {
            let flags = try await flipClient.fetchUnauthenticatedUserFlags()
            self.unauthenticatedUserFlags = flags
        } catch {
            logger.error("Failed to fetch unauthenticated user flags", metadata: ["error": "\(error)"])
        }
    }

    /// Checks whether any of the user's primary accounts is in an unusable
    /// management state and, if so, latches ``requiresForceLogout`` to
    /// `true`. No-op if not logged in or if already latched. Failures are
    /// logged but leave the cached value unchanged so transient errors
    /// don't flip the user into the force-logout modal.
    private func checkForUnusableAccount() async {
        guard case .loggedIn(let sessionContainer) = state else { return }
        guard !requiresForceLogout else { return }
        let owner = sessionContainer.session.ownerKeyPair

        do {
            let accounts = try await client.fetchPrimaryAccounts(owner: owner)
            guard accounts.contains(where: { !$0.managementState.isUsable }) else { return }
            self.requiresForceLogout = true
        } catch {
            logger.error("Failed to check for unusable account", metadata: ["error": "\(error)"])
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
        
        let session = Session(
            container: container,
            historyController: historyController,
            ratesController: ratesController,
            database: database,
            keyAccount: initializedAccount.keyAccount,
            owner: owner,
            userID: initializedAccount.userID
        )
        
        let walletConnection = WalletConnection(owner: owner, client: container.client)

        return SessionContainer(
            session: session,
            database: database,
            walletConnection: walletConnection,
            ratesController: ratesController,
            historyController: historyController,
            pushController: pushController,
            flipClient: container.flipClient
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
            logger.error("Outdated user version, deleted database.")
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
            mint: .usdf, // Initial account is always USDF
            timeAuthority: .usdcAuthority
        )
        
        do {
            let userID: UserID
            
            // Create VM accounts first, this is a no-op
            // if the accounts have been previously created
            try await client.createAccounts(
                owner: cluster.authority.keyPair,
                mint: .usdf, // USDF is the foundation mint
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
            
            logger.debug("Owner", metadata: ["owner": "\(keyAccount.ownerPublicKey)"])

            return InitializedAccount(
                keyAccount: keyAccount,
                userID: userID
            )
            
        } catch {
            ErrorReporting.captureError(
                error,
                reason: isRegistration ? "Failed to register" : "Failed to login"
            )
            throw error
        }
    }
    
    func completeLogin(with initializedAccount: InitializedAccount) {
        logger.debug("completeLogin", metadata: ["owner": "\(initializedAccount.keyAccount.ownerPublicKey)"])
        
        let session = createSessionContainer(
            container: container,
            initializedAccount: initializedAccount
        )
        
        state = .loggedIn(session)
        UserDefaults.wasLoggedIn = true

        Analytics.setIdentity(initializedAccount.userID)

        Task { await checkForUnusableAccount() }
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
        }

        accountManager.resetForLogout()

        state = .loggedOut
        requiresForceLogout = false
        UserDefaults.wasLoggedIn = false

        logger.debug("Logged out")
    }
}

// MARK: - SessionContainer -

struct SessionContainer {

    let session: Session
    let database: Database
    let walletConnection: WalletConnection
    let ratesController: RatesController
    let historyController: HistoryController
    let pushController: PushController
    let flipClient: FlipClient
    let onrampDeeplinkInbox: OnrampDeeplinkInbox
    let onrampCoordinator: OnrampCoordinator

    @MainActor
    init(
        session: Session,
        database: Database,
        walletConnection: WalletConnection,
        ratesController: RatesController,
        historyController: HistoryController,
        pushController: PushController,
        flipClient: FlipClient
    ) {
        self.session = session
        self.database = database
        self.walletConnection = walletConnection
        self.ratesController = ratesController
        self.historyController = historyController
        self.pushController = pushController
        self.flipClient = flipClient
        self.onrampDeeplinkInbox = OnrampDeeplinkInbox()
        self.onrampCoordinator = OnrampCoordinator(session: session, flipClient: flipClient)
    }

    fileprivate func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environment(session)
            .environment(ratesController)
            .environment(historyController)
            .environment(pushController)
            .environment(walletConnection)
            .environment(onrampCoordinator)
            .environment(onrampDeeplinkInbox)
    }

    @MainActor
    static let mock: SessionContainer = .init(
        session: .mock,
        database: .mock,
        walletConnection: .mock,
        ratesController: .mock,
        historyController: .mock,
        pushController: .mock,
        flipClient: Container.mock.flipClient
    )
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
            mint: .usdf, // Initial account is always USDF
            timeAuthority: .usdcAuthority
        )
        self.userID = userID
    }
}

// MARK: - Mock -

extension SessionAuthenticator {
    static let mock: SessionAuthenticator = SessionAuthenticator(container: .mock)
}
