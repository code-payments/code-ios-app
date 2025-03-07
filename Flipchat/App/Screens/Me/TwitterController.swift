//
//  TwitterController.swift
//  Flipchat
//
//  Created by Dima Bart on 2024-03-19.
//

import Foundation
import FlipchatServices
import TwitterAPIKit
import AuthenticationServices

@MainActor
class TwitterController: ObservableObject {
    
    @Published private(set) var state: State = .notAuthorized
    
    private let chatController: ChatController
    private let owner: KeyPair
    
    private let authClient = TwitterAPIClient(.requestOAuth20WithPKCE(.publicClient))
    private let redirectURI = "flipchat://app.flipchat.xyz/oauth/x"
    private let contextProvider = GlobalContextProvider()
    
    private let clientID: String
    
    // MARK: - Init -
    
    init(chatController: ChatController, owner: KeyPair) {
        self.chatController = chatController
        self.owner = owner
        
        self.clientID = try! InfoPlist.value(for: "twitter").value(for: "clientID").string()
        
//        updateState()
    }
    
//    private func updateState() {
//        if let link = Keychain.oauthTwitterToken {
//            let token = link.accessToken
//            if !token.isExpired {
//                state = .authorized(token)
//            } else {
//                state = .expired(token)
//            }
//            
//        } else {
//            state = .notAuthorized
//        }
//    }
    
    // MARK: - Auth -
    
    func authorize() async throws {
        let state = OAuthState()
        let code  = try await authorizeTwitterClient(state: state)
        let token = try await exchangeAuthorizationForAccessToken(code: code, state: state)
        
//        saveToken(token)
        
        try await chatController.linkSocialAccount(token: token.accessToken)
    }
    
    func unlink(socialID: String) async throws {
        try await chatController.unlinkSocialAccount(socialID: socialID)
    }
    
//    private func saveToken(_ token: TwitterAccessToken) {
//        Keychain.oauthTwitterToken = AccessTokenLink.init(owner: owner.publicKey, accessToken: token)
//        updateState()
//    }
    
    private func authorizeTwitterClient(state: OAuthState) async throws -> String {
        /// Ref: https://developer.twitter.com/en/docs/authentication/oauth-2-0/authorization-code
        let url = authClient.auth.makeOAuth2AuthorizeURL(.init(
            responseType: "code",
            clientID: clientID,
            redirectURI: redirectURI,
            state: state.state,
            codeChallenge: state.challenge,
            codeChallengeMethod: "S256",
            scopes: [
                "tweet.read",
                "users.read",
                "offline.access",
            ]
        ))!
        
        return try await withCheckedThrowingContinuation { c in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme("flipchat")) { callbackURL, error in
                guard
                    let callbackURL = callbackURL,
                    let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
                    let code = queryItems.first(where: { $0.name == "code" })?.value,
                    let stateValue = queryItems.first(where: { $0.name == "state" })?.value
                else {
                    if let error {
                        print("Invalid callback. Error: \(error)")
                    }
                    c.resume(with: .failure(Error.invalidCallback))
                    return
                }
                
                // The `state` was set in the original call to authenticate()
                // and will be returned as part of the round trip to Twitter
                // If the state doesn't match, it was this instance that issued
                // the authorization code
                guard stateValue == state.state else {
                    print("State mismatch. Twitter auth returned a state value that was not provided by the client in this session.")
                    c.resume(with: .failure(Error.invalidState))
                    return
                }
                
                print("Received authorization Code: \(code)")
                c.resume(with: .success(code))
            }
            
            session.presentationContextProvider = contextProvider
            
            session.start()
        }
    }
    
    private func exchangeAuthorizationForAccessToken(code: String, state: OAuthState) async throws -> TwitterAccessToken {
        try await withCheckedThrowingContinuation { c in
            /// Ref: https://developer.twitter.com/en/docs/authentication/oauth-2-0/user-access-token
            authClient.auth.postOAuth2AccessToken(.init(
                code: code,
                clientID: clientID,
                redirectURI: redirectURI,
                codeVerifier: state.verifier
            ))
            .responseObject { response in
                switch response.result {
                case .success(let token):
                    let accessToken = TwitterAccessToken(token)
                    c.resume(with: .success(accessToken))
                    
                case .failure(let error):
                    print(error)
                    c.resume(with: .failure(error))
                }
            }
        }
    }
}

// MARK: - AccessToken Box -

//private struct AccessTokenLink: Equatable, Hashable, Codable {
//    let owner: PublicKey
//    let accessToken: TwitterAccessToken
//    
//}

// MARK: - OAuthState -

extension TwitterController {
    struct OAuthState {
        
        let verifier: String
        let challenge: String
        let state: String
        
        init() {
            verifier  = Self.encoded(PublicKey.generate()!.data)
            challenge = Self.encoded(SHA256.digest(verifier))
            state     = Self.encoded(PublicKey.generate()!.data)
        }
        
        private static func encoded(_ data: Data) -> String {
            data
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
    }
}

// MARK: - Error -

extension TwitterController {
    enum Error: Swift.Error {
        case invalidCallback
        case invalidState
    }
}

// MARK: - State -

extension TwitterController {
    enum State {
        case authorized(TwitterAccessToken)
        case expired(TwitterAccessToken)
        case notAuthorized
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding -

private class GlobalContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.appDelegate.window!
    }
}

// MARK: - TwitterAccessToken -

extension TwitterAccessToken {
    init(_ token: TwitterOAuth2AccessToken) {
        self.init(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? "",
            expiresIn: token.expiresIn,
            scope: token.scope
        )
    }
}

// MARK: - Keychain -

//private extension Keychain {
//    @SecureCodable(.twitterToken)
//    static var oauthTwitterToken: AccessTokenLink?
//}

extension TwitterController {
    static let mock = TwitterController(chatController: .mock, owner: .mock)
}
