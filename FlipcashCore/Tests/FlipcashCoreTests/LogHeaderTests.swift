import Foundation
import Testing
@testable import FlipcashCore

@Suite("LogHeader Tests")
struct LogHeaderTests {

    private func render(userID: String? = "user-42", ocp: String = "0.5.0 (82202912)") -> String {
        LogHeader.render(
            appVersion: "1.14.0",
            appBuild: "2201",
            bundleIdentifier: "com.flipcash.app",
            userID: userID,
            device: "iPhone17,1",
            operatingSystem: "Version 18.4 (Build 22E240)",
            architecture: "arm64",
            locale: "en_US",
            timeZone: "America/New_York",
            ocpContract: ocp,
            flipcash2Contract: "0.9.0 (e1f4116c)",
            exportedAt: Date(timeIntervalSince1970: 1_758_030_123)
        )
    }

    @Test("renders every field with aligned labels")
    func rendersEveryField() {
        let header = render()

        #expect(header.contains("DEVICE & APP INFO"))
        #expect(header.contains("App Version:    1.14.0 (2201)"))
        #expect(header.contains("Bundle:         com.flipcash.app"))
        #expect(header.contains("User ID:        user-42"))
        #expect(header.contains("Device:         iPhone17,1"))
        #expect(header.contains("OS:             Version 18.4 (Build 22E240)"))
        #expect(header.contains("Arch:           arm64"))
        #expect(header.contains("Locale:         en_US"))
        #expect(header.contains("Timezone:       America/New_York"))
        #expect(header.contains("OCP Contract:   0.5.0 (82202912)"))
        #expect(header.contains("FC2 Contract:   0.9.0 (e1f4116c)"))
        #expect(header.contains("Exported:       2025-09-16T"))
    }

    @Test("a missing user id reads 'not set' rather than an empty field")
    func missingUserID() {
        #expect(render(userID: nil).contains("User ID:        not set"))
    }

    @Test("a local contract sync is visible in the header")
    func localContract() {
        #expect(render(ocp: "0.5.0-SNAPSHOT (LOCAL)").contains("OCP Contract:   0.5.0-SNAPSHOT (LOCAL)"))
    }

    @Test("the live header names both contract packages")
    func liveHeaderNamesBothContracts() {
        let header = LogHeader.current()
        #expect(header.contains("OCP Contract:"))
        #expect(header.contains("FC2 Contract:"))
        #expect(header.hasPrefix("="))
    }
}
