//
//  StreamReference.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine
import GRPC

class StreamReference<Request, Response>: Cancellable {
    
    var stream: ServerStreamingCall<Request, Response>?
    
    init() {}
    
    init(stream: ServerStreamingCall<Request, Response>) {
        self.stream = stream
    }
    
    deinit {
        trace(.note, components: "Deallocating stream reference: \(Request.self)")
    }
    
    func cancel() {
        stream?.cancel(promise: nil)
    }
}

class BidirectionalStreamReference<Request, Response>: Cancellable {
    
    var stream: BidirectionalStreamingCall<Request, Response>?
    
    private var closure: (() -> Void)?
    
    init() {}
    
    init(stream: BidirectionalStreamingCall<Request, Response>) {
        self.stream = stream
    }
    
    deinit {
        trace(.note, components: "Deallocating bidirectional stream reference: \(Request.self)")
    }
    
    func cancel() {
        stream?.cancel(promise: nil)
    }
    
    func retain() {
        closure = { _ = self }
    }
    
    func release() {
        closure = nil
    }
}
