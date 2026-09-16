//
//  ContractInfoRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashAPI

/// One backend contract package, as the build carries it.
///
/// `commit` is the upstream proto commit the package was generated from, already shortened by the
/// package itself so both platforms truncate the same way. A package built from a local proto sync
/// reports `LOCAL` instead of a SHA -- that build's contract is not reproducible from anything
/// published, which is worth seeing at a glance.
struct ContractInfo: Identifiable {

    let name: String
    let version: String
    let commit: String
    let isLocal: Bool

    var id: String { name }
    var detail: String { "\(version) · \(commit)" }

    static let all: [ContractInfo] = [
        ContractInfo(
            name: "ocp",
            version: OCPContractInfo.version,
            commit: OCPContractInfo.shortProtoCommit,
            isLocal: OCPContractInfo.isLocal
        ),
        ContractInfo(
            name: "flipcash2",
            version: Flipcash2ContractInfo.version,
            commit: Flipcash2ContractInfo.shortProtoCommit,
            isLocal: Flipcash2ContractInfo.isLocal
        ),
    ]
}

/// A read-only row: package name on the left, version and pin on the right.
struct ContractInfoRow: View {

    let info: ContractInfo

    var body: some View {
        Row(insets: .init(top: 10, leading: 20, bottom: 10, trailing: 20)) {
            Text(info.name)
                .font(.appTextMedium)
                .foregroundStyle(.textMain)

            Spacer()

            Text(info.detail)
                .font(.appTextSmall)
                .foregroundStyle(info.isLocal ? Color.textWarning : Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("contract-row-\(info.name)")
    }
}
