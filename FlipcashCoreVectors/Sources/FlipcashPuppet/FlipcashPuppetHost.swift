//
//  FlipcashPuppetHost.swift
//  FlipcashPuppet
//

import Foundation

/// What a launched route runs until the next `launch`: it answers `ls` and `do` for its screens.
public protocol PuppetSession {
    mutating func handle(_ request: JSON) -> JSON
}

/// The Flipcash app's Puppet host: every hosted screen, keyed by the route `launch` takes, behind
/// the request and response shapes in the orchestrator's `docs/puppet/PROTOCOL.md`.
/// `ChatsBehaviorTests` replays the shared behavior files through it in-process, and
/// `flipcash-puppet-host` answers the same requests as lines on stdin for the orchestrator's
/// `puppet` CLI. A new screen adds its route to ``routes``, not a new process.
public struct FlipcashPuppetHost {

    /// Each hosted route and how to start its session. The first is what `reset` and a `launch`
    /// without a route start.
    public static let routes: [(route: String, start: () -> any PuppetSession)] = [
        (ChatsPuppetHost.route, { ChatsPuppetHost() }),
    ]

    private var session: any PuppetSession

    public init() {
        session = Self.routes[0].start()
    }

    /// Answers one request object. `launch` and `reset` start a fresh session; the session answers
    /// everything else.
    public mutating func handle(_ request: JSON) -> JSON {
        guard case .object(let req) = request, case .string(let cmd)? = req["cmd"] else {
            return ChatsPuppetHost.error(.badRequest, "a request is an object with a cmd")
        }
        switch cmd {
        case "launch":
            let route: String
            switch req["route"] {
            case nil, .null?: route = Self.routes[0].route
            case .string(let r)?: route = r
            default: return ChatsPuppetHost.error(.badRequest, "route must be a string")
            }
            guard let entry = Self.routes.first(where: { $0.route == route }) else {
                let known = Self.routes.map(\.route).joined(separator: ", ")
                return ChatsPuppetHost.error(.badInput, "This host launches \(known), not \(route)")
            }
            session = entry.start()
        case "reset":
            session = Self.routes[0].start()
        default:
            return session.handle(request)
        }
        return session.handle(.object(["cmd": .string("ls")]))
    }

    /// Answers one request line with one response line.
    public mutating func handle(line: String) -> String {
        let response: JSON
        if let request = try? JSONDecoder().decode(JSON.self, from: Data(line.utf8)) {
            response = handle(request)
        } else {
            response = ChatsPuppetHost.error(.badRequest, "not JSON")
        }
        let data = (try? JSONEncoder().encode(response)) ?? Data(#"{"ok":false}"#.utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
