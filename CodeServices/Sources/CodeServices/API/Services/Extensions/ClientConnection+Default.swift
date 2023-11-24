//
//  ClientConnection+Default.swift
//  CodeServices
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
        .withErrorDelegate(CodeServiceErrorDelegate())
//        .withKeepalive(
//            .init(interval: .seconds(30), permitWithoutCalls: true)
//        )
//        .withConnectionIdleTimeout(.minutes(5))
//        .withConnectionTimeout(minimum: .minutes(1))
        .connect(host: host, port: port)
    }
}
