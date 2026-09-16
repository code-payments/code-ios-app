import Foundation
import Testing
@testable import Flipcash

@Suite("ContractInfo Tests") @MainActor
struct ContractInfoTests {

    @Test("both contracts are listed, in a stable order")
    func bothContractsListed() {
        #expect(ContractInfo.all.map(\.name) == ["ocp", "flipcash2"])
    }

    @Test("detail joins the version and the short commit")
    func detailJoinsVersionAndCommit() {
        let info = ContractInfo(name: "ocp", version: "0.5.0", commit: "82202912", isLocal: false)
        #expect(info.detail == "0.5.0 · 82202912")
        #expect(info.isLocal == false)
    }

    @Test("a local contract keeps LOCAL in the detail and flags itself")
    func localContract() {
        let info = ContractInfo(name: "ocp", version: "0.5.0", commit: "LOCAL", isLocal: true)
        #expect(info.detail == "0.5.0 · LOCAL")
        #expect(info.isLocal == true)
    }

    @Test("the real packages report a non-empty version and commit")
    func realPackagesReportValues() {
        for info in ContractInfo.all {
            #expect(!info.version.isEmpty, "\(info.name) has no version")
            #expect(!info.commit.isEmpty, "\(info.name) has no commit")
        }
    }
}
