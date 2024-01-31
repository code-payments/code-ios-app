//
//  BucketScreen.swift
//  Code
//
//  Created by Dima Bart on 2023-02-03.
//

import SwiftUI
import CodeUI
import CodeServices

struct BucketScreen: View {
    
    @EnvironmentObject private var exchange: Exchange
    
    @Binding public var isPresented: Bool
    
    private let organizer: Organizer
    private let fragments: [AccountFragment]
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, organizer: Organizer) {
        self._isPresented = isPresented
        self.organizer = organizer
        self.fragments = organizer.mapAccounts { cluster, info in
            AccountFragment(
                cluster: cluster,
                info: info
            )
        }.sorted { lhs, rhs in
            if case .relationship = lhs.info.accountType, case .relationship = rhs.info.accountType {
                return lhs.accountType.caseInsensitiveCompare(rhs.accountType) == .orderedAscending
            } else {
                return lhs.sortOrder < rhs.sortOrder
            }
        }
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                ScrollBox(color: .backgroundMain) {
                    LazyTable(contentPadding: .scrollBox) {
                        rows()
                    }
                }
            }
            .navigationBarTitle(Text("Buckets"), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
        }
        .onAppear {
            Analytics.open(screen: .buckets)
            ErrorReporting.breadcrumb(.bucketScreen)
        }
    }
    
    @ViewBuilder private func rows() -> some View {
        ForEach(fragments) { fragment in
            row(for: fragment)
                .contextMenu(ContextMenu {
                    Button {
                        copyVaultAddress(cluster: fragment.cluster)
                    } label: {
                        Label("Copy Vault Address", systemImage: SystemSymbol.doc.rawValue)
                    }
                })
        }
    }
    
    @ViewBuilder private func row(for fragment: AccountFragment) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 15) {
                    Text(fragment.accountType)
                        .foregroundColor(.textMain)
                    if fragment.info.index > 0 {
                        Text("\(fragment.info.index)")
                            .foregroundColor(.textSecondary)
                    }
                }
                .font(.appTextMedium)
                
                Text(fragment.cluster.vaultPublicKey.base58)
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
                    .truncationMode(.middle)
                    .frame(maxWidth: 130, alignment: .leading)
                HStack {
                    Badge(decoration: .circle(fragment.managementColor), text: fragment.managementTitle)
                    Text(fragment.blockchainTitle)
                        .font(.appTextSmall)
                        .foregroundColor(.textSecondary)
                }
            }
            .padding([.top, .bottom], 15)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 5) {
                Text(fragment.info.balance.formattedFiat(rate: exchange.localRate, suffix: nil))
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                Text(fragment.info.balance.formattedTruncatedKin())
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
                Text(fragment.balanceSourceTitle)
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
            }
            .padding([.top, .bottom], 15)
        }
        .lineLimit(1)
        .padding(.trailing, 20)
        .vSeparator(color: .rowSeparator)
        .padding(.leading, 20)
    }
    
    // MARK: - Actions -
    
    private func copyVaultAddress(cluster: AccountCluster) {
        UIPasteboard.general.string = cluster.vaultPublicKey.base58
    }
}

// MARK: - Previews -

struct BucketScreen_Previews: PreviewProvider {
    static var previews: some View {
        BucketScreen(
            isPresented: .constant(true),
            organizer: .mock2
        )
        .environmentObjectsForSession()
    }
}

// MARK: - Fragment -

private struct AccountFragment: Identifiable {
    
    let id: PublicKey
    let cluster: AccountCluster
    let info: AccountInfo
    
    var balanceSourceTitle: String {
        "\(info.balanceSource)".trimmingCharacters(in: .punctuationCharacters).lowercased()
    }
    
    var blockchainTitle: String {
        "\(info.blockchainState)".trimmingCharacters(in: .punctuationCharacters).capitalized
    }
    
    var managementTitle: String {
        "\(info.managementState)".trimmingCharacters(in: .punctuationCharacters).capitalized
    }
    
    var managementColor: Color {
        switch info.managementState {
        case .locked:
            return .textSuccess
        case .locking, .closing, .unlocking:
            return .textWarning
        case .none, .closed, .unlocked, .unknown:
            return .textError
        }
    }
    
    var accountType: String {
        switch info.accountType {
        case .primary:
            return "Primary"
        case .incoming:
            return "Incoming"
        case .outgoing:
            return "Outgoing"
        case .bucket(let slotType):
            switch slotType {
            case .bucket1:
                return "1"
            case .bucket10:
                return "10"
            case .bucket100:
                return "100"
            case .bucket1k:
                return "1k"
            case .bucket10k:
                return "10k"
            case .bucket100k:
                return "100k"
            case .bucket1m:
                return "1m"
            }
        case .remoteSend:
            return "Remote Send"
        case .swap:
            return "Swap (USDC)"
        case .relationship(let domain):
            return "\(domain.relationshipHost)"
        }
    }
    
    var sortOrder: Int {
        switch info.accountType {
        case .primary:
            return 1
        case .incoming:
            return 2
        case .outgoing:
            return 3
        case .bucket(let slotType):
            switch slotType {
            case .bucket1:
                return 4
            case .bucket10:
                return 5
            case .bucket100:
                return 6
            case .bucket1k:
                return 7
            case .bucket10k:
                return 8
            case .bucket100k:
                return 9
            case .bucket1m:
                return 10
            }
        case .swap:
            return 11
        case .relationship:
            return 12
        case .remoteSend:
            return 13
        }
    }
    
    init(cluster: AccountCluster, info: AccountInfo) {
        self.id = cluster.authority.keyPair.publicKey
        self.cluster = cluster
        self.info = info
    }
}
