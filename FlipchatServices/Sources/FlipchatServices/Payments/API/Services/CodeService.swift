//
//  CodeService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Logging
import GRPC
import NIO

class CodeService<T> where T: GRPCClientType {
    
    let channel: ClientConnection
    let queue: DispatchQueue
    
    let service: T
    
    // MARK: - Init -
    
    public init(channel: ClientConnection, queue: DispatchQueue) {
        self.channel = channel
        self.queue   = queue
        self.service = T(channel: channel)
        
        self.channel.connectivity.delegate = self
    }
}

extension CodeService: ConnectivityStateDelegate {
    public func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
        trace(.note, components: "## Code ##", "Changed \(oldState) -> \(newState)")
    }
    
    public func connectionStartedQuiescing() {
        trace(.note, components: "## Code ##", "Started quiescing")
    }
}

final class CodeServiceErrorDelegate: NSObject, ClientErrorDelegate {
    override init() {
        super.init()
        
    }
    
    func didCatchError(_ error: Error, logger: Logger, file: StaticString, line: Int) {
        trace(.failure, components: "Error: \(error)", function: "\(file):\(line)")
    }
}
