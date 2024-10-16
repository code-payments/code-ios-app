//
//  TipController.swift
//  Code
//
//  Created by Dima Bart on 2024-04-03.
//

import SwiftUI
import CodeServices

@MainActor
class TipController: ObservableObject {
    
    weak var delegate: TipControllerDelegate?
    
    @Published private(set) var hasBadge: Bool = false
    
    @Published private(set) var twitterUser: TwitterUser?
    
    private(set) var inflightUser: (String, Code.Payload)?
    
    private(set) var userMetadata: TwitterUser?
    
    private(set) var userAvatar: Image?
    
    private let organizer: Organizer
    private let client: Client
    private let bannerController: BannerController
    
    private var cachedUsers: [String: TwitterUser] = [:]
    private var cachedAvatars: [String: Image] = [:]
    
    private var poller: Poller?
    
    @Defaults(.twitterUser) private var authenticatedTwitterUser: TwitterUser?
    
    @Defaults(.hasSeenTipCard) private var hasSeenTipCard: Bool?
    
    @Defaults(.wasPromptedPush) private var wasPromptedPush: Bool?
    
    private var primaryTipAddress: PublicKey {
        organizer.primaryVault
    }
    
    // MARK: - Init -
    
    init(organizer: Organizer, client: Client, bannerController: BannerController) {
        self.organizer = organizer
        self.client = client
        self.bannerController = bannerController
        
        self.hasBadge = hasSeenTipCard == false
        
        if !assignUserIfAuthenticated() {
            poll()
        }
        
        NotificationCenter.default.addObserver(forName: .twitterNotificationReceived, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.pushNotificationReceived()
            }
        }
    }
    
    // MARK: - Badge -
    
    func setHasSeenTipCard() {
        hasSeenTipCard = true
        hasBadge = false
    }
    
    private func resetHasSeenTipCard() {
        hasSeenTipCard = false
        hasBadge = true
        
        resetPushPrompted()
    }
    
    // MARK: - Push -
    
    private func pushNotificationReceived() {
        poll()
    }
    
    func shouldPromptForPushPermissions() async -> Bool {
        if wasPromptedPush != true {
            let status = await PushController.getAuthorizationStatus()
            if status != .authorized {
                return true
            }
        }
        return false
    }
    
    func setPushPrompted() {
        wasPromptedPush = true
    }
    
    private func resetPushPrompted() {
        wasPromptedPush = false
    }
    
    // MARK: - Polling -
    
    func didOpenTwitter() {
        startPolling()
    }
    
    private func startPolling() {
        self.poller = Poller(seconds: 5) { [weak self] in
            self?.poll()
        }
    }
    
    private func cancelPolling() {
        poller = nil
    }
    
    private func poll() {
        Task {
            do {
                let user = try await client.fetchTwitterUser(query: .tipAddress(primaryTipAddress))
                
                store(authenticatedUser: user)
                assignUserIfAuthenticated()
                
                showLinkingSuccess(for: user)
                cancelPolling()
                
                resetHasSeenTipCard()
                
                Analytics.tipCardLinked()
                
            } catch {
                // Continue polling
            }
        }
    }
    
    // MARK: - Authenticated User -
    
    private func store(authenticatedUser: TwitterUser) {
        authenticatedTwitterUser = authenticatedUser
    }
    
    func deleteAuthenticatedUser() {
        authenticatedTwitterUser = nil
        twitterUser = nil
    }
    
    @discardableResult
    private func assignUserIfAuthenticated() -> Bool {
        guard let user = authenticatedTwitterUser else {
            return false
        }
        
        twitterUser = user
        return true
    }
    
    func prepareForLogout() {
        deleteAuthenticatedUser()
    }
    
    // MARK: - Actions -
    
    func fetchUser(username: String, payload: Code.Payload) async throws {
        inflightUser = (username, payload)
        
        let metadata = try await fetch(username: username)
        userMetadata = metadata
        userAvatar = try? await fetchAvatar(username: username, url: metadata.avatarURL)
    }
    
    func fetch(username: String) async throws -> TwitterUser {
        let key = username.lowercased()
        
        if let cachedUser = cachedUsers[key] {
            return cachedUser
        }
        
        let user = try await client.fetchTwitterUser(query: .username(username))
        
        cachedUsers[key] = user
        
        return user
    }
    
    func fetchAvatar(username: String, url: URL) async throws -> Image {
        let key = username.lowercased()
        
        if let cachedAvatar = cachedAvatars[key] {
            return cachedAvatar
        }
        
        let avatarURL = AvatarURL(profileImageString: url.absoluteString)
        let avatar = try await ImageLoader.shared.load(avatarURL.original)
        
        cachedAvatars[key] = avatar
        
        return avatar
    }
    
    func resetInflightUser() {
        inflightUser = nil
        userMetadata = nil
    }
    
    // MARK: - Auth Message -
    
    func generateTwitterAuthMessage(nonce: UUID) -> String {
        let signature = organizer.ownerKeyPair.sign(nonce.data)
        let components = [
            "CodeAccount",
            primaryTipAddress.base58,
            Base58.fromBytes(nonce.bytes),
            signature.base58,
        ]
        
        let auth = components.joined(separator: ":")
        let message = "\(Localized.Subtitle.connectXTweetText)\n\n\(auth)"
        
        return message
    }
    
    private func generateNudgeText(for username: String) -> String {
        "Hey @\(username) you should set up your @getcode Tip Card so I can tip you some cash.\n\ngetcode.com/download"
    }
    
    func openTwitterWithAuthenticationText(nonce: UUID) {
        let message = generateTwitterAuthMessage(nonce: nonce).addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let url = URL.tweet(content: message)
        
        didOpenTwitter()
        
        url.openWithApplication()
    }
    
    func openTwitterWithNudgeText(username: String) {
        let message = generateNudgeText(for: username).addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let url = URL.tweet(content: message)
        
        didOpenTwitter()
        
        url.openWithApplication()
    }
    
    // MARK: - Actions -
    
    private func showTipCard(for user: TwitterUser) {
        delegate?.willShowTipCard(for: user)
    }
    
    // MARK: - Banners -
    
    private func showLinkingSuccess(for user: TwitterUser) {
        bannerController.show(
            style: .success(.checkmark(.textSuccess)),
            title: Localized.Success.Title.xConnected,
            description: Localized.Success.Description.xConnected,
            actions: [
                .prominent(title: Localized.Action.showMyTipCard) { [weak self] in
                    self?.showTipCard(for: user)
                },
                .cancel(title: Localized.Action.later),
            ]
        )
    }
}

// MARK: - Delegate -

protocol TipControllerDelegate: AnyObject {
    func willShowTipCard(for user: TwitterUser)
}

// MARK: - AvatarURL -

struct AvatarURL {
    
    let normal: URL
    let bigger: URL
    let mini: URL
    let original: URL
    
    // MARK: - Init -
    
    init(normal: URL, bigger: URL, mini: URL, original: URL) {
        self.normal = normal
        self.bigger = bigger
        self.mini = mini
        self.original = original
    }
    
    init(profileImageString: String) {
        let suffixes: Set = [
            "_normal",
            "_bigger",
            "_mini",
            "_original",
        ]
        
        var string = profileImageString
        
        suffixes.forEach { suffix in
            string = string.replacingOccurrences(of: suffix, with: "")
        }
        
        let baseURL = URL(string: string)!
        
        let imagePath = baseURL.lastPathComponent
        var components = imagePath.components(separatedBy: ".")
        if components.count == 2 {
            components[0] = "\(components[0])"
        }
        
        self.init(
            normal:   Self.applying(suffix: "_normal", to: baseURL),
            bigger:   Self.applying(suffix: "_bigger", to: baseURL),
            mini:     Self.applying(suffix: "_mini",   to: baseURL),
            original: baseURL
        )
    }
    
    private static func applying(suffix: String, to baseURL: URL) -> URL {
        let separator = "."
        let imagePath = baseURL.lastPathComponent
        
        var components = imagePath.components(separatedBy: separator)
        if components.count == 2 {
            components[0] = "\(components[0])\(suffix)"
        }
        let newImagePath = components.joined(separator: separator)
        
        var updatedURL = baseURL
        
        updatedURL.deleteLastPathComponent()
        updatedURL.appendPathComponent(newImagePath)
        
        return updatedURL
    }
}

// MARK: - Image Loader -

class ImageLoader {
    
    static let shared = ImageLoader()
    
    private init() {}
    
    func load(_ url: URL) async throws -> Image {
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let image = UIImage(data: data) else {
            throw Error.invalidImageData
        }
        
        return Image(uiImage: image)
    }
}

extension ImageLoader {
    enum Error: Swift.Error {
        case invalidImageData
    }
}

extension TipController {
    static let mock = TipController(
        organizer: .mock,
        client: .mock,
        bannerController: .mock
    )
}
