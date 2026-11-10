//
//  ChatsBehaviorTests.swift
//  FlipcashCoreVectorsTests
//

import Foundation
import Testing
import FlipcashPuppet

/// Replays `test-vectors/behaviors/chats/*.json` through ``FlipcashPuppetHost``, the seeded
/// ``ChatsModel`` the `flipcash-puppet-host` process also serves. Synced copy: a failure is fixed in the canonical files in the orchestrator or
/// in `ChatsModel`, never by editing the copy here.
@Suite("Chats behaviors")
struct ChatsBehaviorTests {

    @Test("Every Chats behavior file replays as written")
    func behaviors() throws {
        let urls = try #require(
            Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/behaviors/chats")
        )
        #expect(!urls.isEmpty, "no behavior files bundled")
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let behavior = try JSONDecoder().decode(Behavior.self, from: Data(contentsOf: url))
            replay(behavior, file: url.lastPathComponent)
        }
    }

    /// Sends each step to ``FlipcashPuppetHost/handle(_:)``, the same request path the CLI uses:
    /// `launch` first, then `ls` or `do` per step, matching `expectPath` exactly and `expect` as a
    /// subset of the top node's state.
    private func replay(_ behavior: Behavior, file: String) {
        var host = FlipcashPuppetHost()
        var launch: [String: JSON] = ["cmd": .string("launch")]
        if let route = behavior.route { launch["route"] = .string(route) }
        guard case .object(let first) = host.handle(.object(launch)), first["ok"] == .bool(true),
              case .object(let node)? = first["node"], node["name"] == .string(behavior.screen) else {
            Issue.record("\(file): launch didn't open \(behavior.screen)")
            return
        }
        for (index, step) in behavior.steps.enumerated() {
            let label = "\(file): step \(index + 1) (\(step.do ?? "ls"))"
            var request: [String: JSON] = ["cmd": .string(step.do == nil ? "ls" : "do")]
            if let action = step.do {
                request["action"] = .string(action)
                request["input"] = .object(step.input ?? [:])
            }
            guard case .object(let response) = host.handle(.object(request)) else {
                Issue.record("\(label): response isn't an object")
                return
            }
            if response["ok"] != .bool(true) {
                var code = "?"
                if case .object(let error)? = response["error"], case .string(let c)? = error["code"] { code = c }
                if let expected = step.expectError {
                    #expect(code == expected, "\(label): expected error \(expected), got \(code)")
                    continue
                }
                Issue.record("\(label): unexpected error \(code)")
                return
            }
            if let expected = step.expectError {
                Issue.record("\(label): expected error \(expected), got success")
                continue
            }
            if let want = step.expectPath {
                let got = response["path"] ?? .null
                #expect(got == .array(want.map(JSON.string)), "\(label): path: expected \(want), got \(got)")
            }
            guard case .object(let top)? = response["node"], case .object(let state)? = top["state"] else {
                Issue.record("\(label): response has no node state")
                return
            }
            for (key, want) in step.expect ?? [:] {
                guard let got = state[key] else {
                    Issue.record("\(label): state.\(key): missing on iOS")
                    continue
                }
                #expect(got == want, "\(label): state.\(key): expected \(want), got \(got)")
            }
        }
    }
}

// MARK: - File format

private struct Behavior: Decodable {
    struct Step: Decodable {
        let `do`: String?
        let input: [String: JSON]?
        let expect: [String: JSON]?
        let expectError: String?
        let expectPath: [String]?
    }
    let screen: String
    let route: String?
    let steps: [Step]
}
