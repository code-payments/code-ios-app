//
//  FlipchatClient.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import CodeServices
import Foundation
import Combine
import NIO
import GRPC

@MainActor
public class FlipchatClient: ObservableObject {
    
    public let network: Network
    public let channel: ClientConnection
    
    public let queue: DispatchQueue
    
//    internal let identityService: IdentityService
    internal let chatService: ChatService
    
    // MARK: - Init -
    
    public init(network: Network, queue: DispatchQueue = .main) {
        self.network = network
        self.queue   = queue
        self.channel = ClientConnection.appConnection(
            host: network.host,
            port: network.port
        )
        
//        self.identityService = IdentityService(channel: channel, queue: queue)
        self.chatService     = ChatService(channel: channel, queue: queue)
    }
    
    deinit {
        trace(.warning, components: "Deallocating Client")
    }
}

// MARK: - Error -

public enum ClientError: Error {
    case pollLimitReached
}

public enum ErrorGeneric: Error {
    case unknown
}
