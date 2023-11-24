//
//  ConnectionPool.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import GRPC
import NIO

public class ConnectionPool {
    
    private var connections: [String: ClientConnection] = [:]
    
    // MARK: - Init -
    
    public init() {}
    
    public func connection(host: String, port: Int) -> ClientConnection {
        let key = key(for: host, port: port)
        
        guard let connection = connections[key] else {
            let newConnection = ClientConnection.appConnection(
                host: host,
                port: port
            )
            
            connections[key] = newConnection
            return newConnection
        }
        
        return connection
    }
    
    private func key(for host: String, port: Int) -> String {
        "\(host):\(port)"
    }
}
