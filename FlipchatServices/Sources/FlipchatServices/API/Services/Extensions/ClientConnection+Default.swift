//
//  ClientConnection+Default.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import GRPC
import NIO

extension ClientConnection {
    public static func appConnection(host: String, port: Int) -> ClientConnection {
        .usingTLSBackedByNIOSSL(on: MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount))
        .withErrorDelegate(FlipchatServiceErrorDelegate())
        .connect(host: host, port: port)
    }
}
