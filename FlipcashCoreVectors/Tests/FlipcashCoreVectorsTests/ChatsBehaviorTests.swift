//
//  ChatsBehaviorTests.swift
//  FlipcashCoreVectorsTests
//

import Foundation
import Testing
import ChatsPuppet

/// Replays `test-vectors/behaviors/chats/*.json` through ``ChatsPuppetHost``, the seeded
/// ``ChatsModel`` the `chats-puppet-host` process also serves. Synced copy: a failure is fixed in the canonical files in the orchestrator or
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

    private func replay(_ behavior: Behavior, file: String) {
        var host = ChatsPuppetHost()
        for (index, step) in behavior.steps.enumerated() {
            let label = "\(file): step \(index + 1) (\(step.do ?? "ls"))"
            let result = step.do.map { host.perform($0, input: step.input ?? [:]) } ?? .success(())
            switch (result, step.expectError) {
            case (.failure(let code), let expected?):
                #expect(code.rawValue == expected, "\(label): expected error \(expected), got \(code.rawValue)")
                continue
            case (.failure(let code), nil):
                Issue.record("\(label): unexpected error \(code.rawValue)")
                return
            case (.success, let expected?):
                Issue.record("\(label): expected error \(expected), got success")
                continue
            case (.success, nil):
                break
            }
            let state = host.state()
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
    }
    let screen: String
    let steps: [Step]
}
