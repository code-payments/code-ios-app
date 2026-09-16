import Foundation
import FlipcashAPI

/// The block written at the top of an exported log file.
///
/// A log file arriving from a tester says nothing about what produced it. This is the answer to
/// the questions that otherwise cost a round trip: which build, which device, which OS, and --
/// the reason this file exists -- which backend contract the build speaks.
///
/// `render` takes every value so it can be tested; `current` reads them from the running process.
enum LogHeader {

    private static let rule = String(repeating: "=", count: 60)

    static func render(
        appVersion: String,
        appBuild: String,
        bundleIdentifier: String,
        userID: String?,
        device: String,
        operatingSystem: String,
        architecture: String,
        locale: String,
        timeZone: String,
        ocpContract: String,
        flipcash2Contract: String,
        exportedAt: Date
    ) -> String {
        var header = ""
        header += rule + "\n"
        header += "DEVICE & APP INFO\n"
        header += rule + "\n"
        header += "App Version:    \(appVersion) (\(appBuild))\n"
        header += "Bundle:         \(bundleIdentifier)\n"
        header += "User ID:        \(userID ?? "not set")\n"
        header += "Device:         \(device)\n"
        header += "OS:             \(operatingSystem)\n"
        header += "Arch:           \(architecture)\n"
        header += "Locale:         \(locale)\n"
        header += "Timezone:       \(timeZone)\n"
        header += "OCP Contract:   \(ocpContract)\n"
        header += "FC2 Contract:   \(flipcash2Contract)\n"
        header += "Exported:       \(iso8601.string(from: exportedAt))\n"
        header += rule + "\n\n"
        return header
    }

    static func current(userID: String? = nil, exportedAt: Date = Date()) -> String {
        render(
            appVersion: AppMeta.version,
            appBuild: AppMeta.build,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            userID: userID,
            device: deviceIdentifier,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            ocpContract: "\(OCPContractInfo.version) (\(OCPContractInfo.shortProtoCommit))",
            flipcash2Contract: "\(Flipcash2ContractInfo.version) (\(Flipcash2ContractInfo.shortProtoCommit))",
            exportedAt: exportedAt
        )
    }

    // MARK: - Private

    /// `ISO8601DateFormatter` isn't `Sendable`, but this instance is configured once and only
    /// ever used for formatting, so sharing it across isolation domains is safe.
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// The hardware string, e.g. `iPhone17,1`. `UIDevice.current.model` only ever says "iPhone",
    /// and reaching for UIKit here would pull a main-actor dependency into a background export.
    private static var deviceIdentifier: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            Array(raw.prefix(while: { $0 != 0 }))
        }
        let identifier = String(decoding: machine, as: UTF8.self)
        return identifier.isEmpty ? "unknown" : identifier
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
