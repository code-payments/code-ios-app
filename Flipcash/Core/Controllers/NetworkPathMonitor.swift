//
//  NetworkPathMonitor.swift
//  Flipcash
//

import Foundation
import Network
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.network-path")

/// What iOS reports about this app's route to the network.
struct NetworkPathState: Equatable, Sendable {

    /// Whether iOS will let the app open a connection.
    enum Status: String, Sendable {
        case satisfied
        case unsatisfied
        case requiresConnection
    }

    /// Why iOS refuses the app a connection while the device itself may be online.
    enum UnsatisfiedReason: String, Sendable {
        case notAvailable
        case cellularDenied
        case wifiDenied
        case localNetworkDenied
        case vpnInactive
        case unknown
    }

    let status: Status
    let unsatisfiedReason: UnsatisfiedReason?
    let interfaces: [String]
    let isExpensive: Bool
    let isConstrained: Bool
    let supportsIPv4: Bool
    let supportsIPv6: Bool
    let supportsDNS: Bool

    /// Whether the app's Cellular Data switch in Settings is what keeps it offline.
    var isCellularDenied: Bool {
        status != .satisfied && unsatisfiedReason == .cellularDenied
    }

    /// The state assumed before iOS delivers the first path: online, so no dialog blames Settings
    /// before iOS has reported anything.
    static let unknown = NetworkPathState(
        status: .satisfied,
        unsatisfiedReason: nil,
        interfaces: [],
        isExpensive: false,
        isConstrained: false,
        supportsIPv4: true,
        supportsIPv6: true,
        supportsDNS: true
    )
}

extension NetworkPathState {

    nonisolated init(_ path: NWPath) {
        let status: Status = switch path.status {
        case .satisfied:          .satisfied
        case .unsatisfied:        .unsatisfied
        case .requiresConnection: .requiresConnection
        @unknown default:         .unsatisfied
        }

        let reason: UnsatisfiedReason? = switch path.unsatisfiedReason {
        case .notAvailable:       status == .satisfied ? nil : .notAvailable
        case .cellularDenied:     .cellularDenied
        case .wifiDenied:         .wifiDenied
        case .localNetworkDenied: .localNetworkDenied
        case .vpnInactive:        .vpnInactive
        @unknown default:         .unknown
        }

        let interfaces = path.availableInterfaces.map { interface in
            switch interface.type {
            case .wifi:          "wifi"
            case .cellular:      "cellular"
            case .wiredEthernet: "wired"
            case .loopback:      "loopback"
            case .other:         "other"
            @unknown default:    "unknown"
            }
        }

        self.init(
            status: status,
            unsatisfiedReason: reason,
            interfaces: interfaces,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            supportsIPv4: path.supportsIPv4,
            supportsIPv6: path.supportsIPv6,
            supportsDNS: path.supportsDNS
        )
    }
}

/// Tracks the app's network path and logs every change, so an exported log shows why iOS
/// reported the network as down. It lives as long as the process and is never cancelled.
@MainActor
@Observable
final class NetworkPathMonitor {

    /// The most recent path iOS delivered.
    private(set) var state: NetworkPathState = .unknown

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let state = NetworkPathState(path)
            Task { @MainActor in
                self?.update(state)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.flipcash.network-path"))
    }

    private func update(_ newState: NetworkPathState) {
        guard newState != state else { return }
        state = newState
        logger.info("Network path changed", metadata: [
            "status": "\(newState.status.rawValue)",
            "reason": "\(newState.unsatisfiedReason?.rawValue ?? "none")",
            "interfaces": "\(newState.interfaces.joined(separator: ","))",
            "expensive": "\(newState.isExpensive)",
            "constrained": "\(newState.isConstrained)",
            "ipv4": "\(newState.supportsIPv4)",
            "ipv6": "\(newState.supportsIPv6)",
            "dns": "\(newState.supportsDNS)",
        ])
    }
}
