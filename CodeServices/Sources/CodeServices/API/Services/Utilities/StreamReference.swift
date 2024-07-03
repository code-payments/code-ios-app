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

public class BidirectionalStreamReference<Request, Response>: Cancellable {
    
    var stream: BidirectionalStreamingCall<Request, Response>? {
        didSet {
            if stream != nil {
                postponeTimeout()
            } else {
                cancelTimeout()
            }
        }
    }
    
    var timeoutHandler: (() -> Void)?
    
    private(set) var lastPing: Date?
    private(set) var pingTimeout: Int = 15 // seconds
    
    private var closure: (() -> Void)?
    
    private var timeoutTask: Task<Void, Error>?
    
    // MARK: - Init -
    
    init() {}
    
    init(stream: BidirectionalStreamingCall<Request, Response>) {
        self.stream = stream
    }
    
    deinit {
        trace(.note, components: "Deallocating bidirectional stream reference: \(Request.self)")
    }
    
    // MARK: - Ping -
    
    func receivedPing(updatedTimeout: Int? = nil) {
        lastPing = .now
        
        // If the server provides a timeout, 
        // we'll update our local timeout
        // accordingly.
        if let updatedTimeout {
            // Double the server-provided timeout
            let newTimeout = updatedTimeout * 2
            if pingTimeout != newTimeout {
                trace(.warning, components: "Updating timeout from \(pingTimeout) sec to \(newTimeout) sec")
                pingTimeout = newTimeout
            }
        }
        
        postponeTimeout()
    }
    
    func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
    
    func postponeTimeout() {
        cancelTimeout()
        
        timeoutTask = Task { [weak self] in
            guard let self else {
                return
            }
            
            guard !Task.isCancelled else {
                return
            }
            
            try await Task.delay(seconds: self.pingTimeout)
            
            if !Task.isCancelled {
                self.timeoutHandler?()
            }
        }
    }
    
    // MARK: - Cancel -
    
    public func destroy() {
        timeoutHandler = nil
        cancel()
        release()
    }
    
    public func cancel() {
        cancelTimeout()
        stream?.cancel(promise: nil)
    }
    
    // MARK: - Memory -
    
    func retain() {
        closure = { _ = self }
    }
    
    func release() {
        closure = nil
    }
}
