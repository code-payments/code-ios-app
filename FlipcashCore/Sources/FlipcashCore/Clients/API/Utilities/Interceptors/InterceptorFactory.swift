//
//  InterceptorFactory.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import GRPC
import NIO

struct InterceptorFactory: Sendable {
    func makeInterceptors<Request, Response>() -> [ClientInterceptor<Request, Response>] {
        [
            UserAgentInterceptor(),
        ]
    }
}
