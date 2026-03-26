//
//  CodeService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import GRPC
import NIO

protocol GRPCClientType {
    init(channel: GRPCChannel)
}

extension CallOptions {
    /// Default call options for unary gRPC calls. The timeout caps
    /// individual RPCs so they fail fast on dead connections instead
    /// of waiting for the OS-level TCP timeout (~60s).
    static let `default` = CallOptions(
        timeLimit: .timeout(.seconds(15))
    )

    /// For bidirectional and long-lived streams. No gRPC-level deadline;
    /// lifecycle is managed by BidirectionalStreamReference's ping timeout
    /// and application-level reconnection logic.
    static let streaming = CallOptions(
        timeLimit: .none
    )
}

class CodeService<T> where T: GRPCClientType {
    
    let channel: ClientConnection
    let queue: DispatchQueue
    
    let service: T
    
    // MARK: - Init -
    
    public init(channel: ClientConnection, queue: DispatchQueue) {
        self.channel = channel
        self.queue   = queue
        self.service = T(channel: channel)
        
//        self.channel.connectivity.delegate = self
    }
}

//extension CodeService: ConnectivityStateDelegate {
//    public func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
//        trace(.note, components: "## Code ##", "Changed \(oldState) -> \(newState)")
//    }
//    
//    public func connectionStartedQuiescing() {
//        trace(.note, components: "## Code ##", "Started quiescing")
//    }
//}

private let codeServiceLogger = Logger(label: "flipcash.grpc")

final class CodeServiceErrorDelegate: NSObject, ClientErrorDelegate {
    override init() {
        super.init()
    }

    func didCatchError(_ error: Error, logger: Logger, file: StaticString, line: Int) {
        codeServiceLogger.error("gRPC client error at \(file):\(line): \(error)")
    }
}
