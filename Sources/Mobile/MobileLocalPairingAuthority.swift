import CMUXMobileCore
import CmuxControlSocket
import Foundation

/// Issues and verifies persistent, bundle-scoped capabilities for local-only
/// mobile pairing. A capability is useful only together with the exact
/// Tailscale endpoint carried by its pairing code.
struct MobileLocalPairingAuthority: Sendable {
    private let authority: SocketClientCapabilityAuthority

    init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        let normalizedBundleIdentifier = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let audience: String
        if let normalizedBundleIdentifier,
           !normalizedBundleIdentifier.isEmpty {
            audience = normalizedBundleIdentifier
        } else {
            audience = "com.cmuxterm.app"
        }
        let secret: Data
        #if DEBUG
        if let tag = ProcessInfo.processInfo.environment["CMUX_TAG"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !tag.isEmpty,
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first {
            let fileURL = applicationSupport
                .appendingPathComponent("cmux", isDirectory: true)
                .appendingPathComponent("mobile-local-pairing", isDirectory: true)
                .appendingPathComponent("\(audience).secret", isDirectory: false)
            secret = SocketClientCapabilityFileSecretStore(fileURL: fileURL)
                .loadOrCreateSecret()
        } else {
            let store = SocketClientCapabilitySecretStore(
                service: "\(audience).mobile-local-pairing-capability.v1"
            )
            secret = store.loadOrCreateSecret()
        }
        #else
        let store = SocketClientCapabilitySecretStore(
            service: "\(audience).mobile-local-pairing-capability.v1"
        )
        secret = store.loadOrCreateSecret()
        #endif
        authority = SocketClientCapabilityAuthority(
            secret: secret,
            audience: "\(audience).mobile-local-pairing"
        )
    }

    /// Deterministic authority seam for route-binding tests.
    init(secret: Data, audience: String) {
        authority = SocketClientCapabilityAuthority(
            secret: secret,
            audience: audience
        )
    }

    func issueCapability(for routes: [CmxAttachRoute]) throws -> String {
        authority.issueCapability(binding: try Self.binding(for: routes))
    }

    func verifies(_ capability: String?, for routes: [CmxAttachRoute]) -> Bool {
        guard let capability = capability?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !capability.isEmpty else { return false }
        guard let binding = try? Self.binding(for: routes) else { return false }
        return authority.verifies(capability, binding: binding)
    }

    /// Canonicalizes only the disclosed numeric Tailscale destinations. Route
    /// ids, priorities, and ordering do not grant authority, so semantically
    /// identical route sets produce one stable binding.
    private static func binding(for routes: [CmxAttachRoute]) throws -> Data {
        guard !routes.isEmpty else {
            throw MobileLocalPairingAuthorityError.noTailscaleRoutes
        }
        let destinations = try routes.map { route -> String in
            guard route.kind == .tailscale,
                  case let .hostPort(host, port) = route.endpoint else {
                throw MobileLocalPairingAuthorityError.invalidTailscaleRoute
            }
            let destination: CmxUserTailscalePairingAuthorization
            do {
                destination = try CmxUserTailscalePairingAuthorization(
                    host: host,
                    port: port
                )
            } catch {
                throw MobileLocalPairingAuthorityError.invalidTailscaleRoute
            }
            return "\(destination.host.utf8.count):\(destination.host):\(destination.port)"
        }
        let uniqueDestinations = Set(destinations)
        guard uniqueDestinations.count == destinations.count else {
            throw MobileLocalPairingAuthorityError.duplicateTailscaleRoute
        }
        let payload = uniqueDestinations.sorted().joined(separator: "\n")
        return Data("cmux.mobile-local-pairing.routes.v1\0\(payload)".utf8)
    }
}

enum MobileLocalPairingAuthorityError: Error, Equatable, Sendable {
    case noTailscaleRoutes
    case invalidTailscaleRoute
    case duplicateTailscaleRoute
}
