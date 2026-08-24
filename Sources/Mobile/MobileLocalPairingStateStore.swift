import CryptoKit
import Foundation

/// Persistent identity and live-presence projection for the one iPhone owned
/// by account-free Tailscale pairing.
struct MobileLocalPairingDeviceSnapshot: Equatable, Sendable {
    let deviceID: String
    let displayName: String
    let isConnected: Bool
    let lastSeen: Date?
    let activeWorkspaceID: UUID?
    let activeSurfaceID: UUID?
}

/// Owns the single durable local-pairing credential and its connection set.
///
/// Only a SHA-256 fingerprint of the bearer capability is persisted. A fresh
/// store may adopt one already-valid capability to migrate the account-free
/// build that predated paired-device persistence. ``forget()`` writes a
/// tombstone so that migration can never silently resurrect the forgotten
/// credential; only ``preparePairing(capability:)`` opens a new invitation.
@MainActor
final class MobileLocalPairingStateStore {
    private struct ConnectionPresence {
        let deviceID: String
        let displayName: String
        let activeWorkspaceID: UUID?
        let activeSurfaceID: UUID?
        let observedAt: Date
    }

    private let defaults: UserDefaults
    private let keyPrefix: String
    private var activeFingerprint: String?
    private var pendingFingerprint: String?
    private var persistedDeviceID: String?
    private var persistedDisplayName: String?
    private var persistedLastSeen: Date?
    private var connections: [UUID: ConnectionPresence] = [:]

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "cmux.mobile.localPairing.v1"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        activeFingerprint = Self.normalized(defaults.string(forKey: key("fingerprint")))
        persistedDeviceID = Self.normalized(defaults.string(forKey: key("deviceID")))
        persistedDisplayName = Self.normalized(defaults.string(forKey: key("displayName")))
        let lastSeen = defaults.double(forKey: key("lastSeen"))
        persistedLastSeen = lastSeen > 0 ? Date(timeIntervalSince1970: lastSeen) : nil
    }

    var snapshot: MobileLocalPairingDeviceSnapshot? {
        guard let activeFingerprint else { return nil }
        let live = connections.values.max { $0.observedAt < $1.observedAt }
        return MobileLocalPairingDeviceSnapshot(
            deviceID: live?.deviceID
                ?? persistedDeviceID
                ?? "local-\(activeFingerprint.prefix(12))",
            displayName: live?.displayName
                ?? persistedDisplayName
                ?? "iPhone",
            isConnected: !connections.isEmpty,
            lastSeen: live?.observedAt ?? persistedLastSeen,
            activeWorkspaceID: live?.activeWorkspaceID,
            activeSurfaceID: live?.activeSurfaceID
        )
    }

    /// Opens one explicit pairing invitation when no phone is already owned.
    @discardableResult
    func preparePairing(capability: String) -> Bool {
        guard activeFingerprint == nil,
              let fingerprint = Self.fingerprint(capability) else {
            return false
        }
        pendingFingerprint = fingerprint
        defaults.set(false, forKey: key("forgotten"))
        return true
    }

    /// Accepts only the owned or explicitly pending credential. A store that
    /// predates this state adopts its first authority-verified credential once.
    @discardableResult
    func authorize(capability: String) -> Bool {
        guard let fingerprint = Self.fingerprint(capability) else { return false }
        if let activeFingerprint {
            return activeFingerprint == fingerprint
        }
        if let pendingFingerprint {
            guard pendingFingerprint == fingerprint else { return false }
            claim(fingerprint)
            return true
        }
        guard !defaults.bool(forKey: key("forgotten")) else { return false }
        claim(fingerprint)
        return true
    }

    /// Records one authorized transport and its latest device/navigation
    /// metadata. Multiple connections from the same phone are allowed during
    /// reconnect handoff so the status does not flicker offline mid-session.
    @discardableResult
    func recordAuthorizedConnection(
        id: UUID,
        capability: String,
        deviceID: String?,
        displayName: String?,
        activeWorkspaceID: UUID?,
        activeSurfaceID: UUID?,
        at date: Date = Date()
    ) -> Bool {
        guard authorize(capability: capability) else { return false }
        let resolvedDeviceID = Self.normalized(deviceID)
            ?? persistedDeviceID
            ?? "local-\(activeFingerprint?.prefix(12) ?? "phone")"
        if let persistedDeviceID, persistedDeviceID != resolvedDeviceID {
            return false
        }
        let resolvedDisplayName = Self.normalized(displayName)
            ?? persistedDisplayName
            ?? "iPhone"
        if let existing = connections[id],
           existing.deviceID == resolvedDeviceID,
           existing.displayName == resolvedDisplayName,
           existing.activeWorkspaceID == activeWorkspaceID,
           existing.activeSurfaceID == activeSurfaceID {
            return true
        }
        persistedDeviceID = resolvedDeviceID
        persistedDisplayName = resolvedDisplayName
        persistedLastSeen = date
        connections[id] = ConnectionPresence(
            deviceID: resolvedDeviceID,
            displayName: resolvedDisplayName,
            activeWorkspaceID: activeWorkspaceID,
            activeSurfaceID: activeSurfaceID,
            observedAt: date
        )
        persistMetadata()
        return true
    }

    /// Drops one physical connection while retaining the durable pairing.
    func connectionClosed(id: UUID, at date: Date = Date()) {
        guard connections.removeValue(forKey: id) != nil else { return }
        persistedLastSeen = date
        persistMetadata()
    }

    /// Revokes the durable pairing and returns every connection it owned so
    /// the host can close those transports through its normal teardown path.
    @discardableResult
    func forget() -> Set<UUID> {
        let connectionIDs = Set(connections.keys)
        connections.removeAll()
        activeFingerprint = nil
        pendingFingerprint = nil
        persistedDeviceID = nil
        persistedDisplayName = nil
        persistedLastSeen = nil
        defaults.removeObject(forKey: key("fingerprint"))
        defaults.removeObject(forKey: key("deviceID"))
        defaults.removeObject(forKey: key("displayName"))
        defaults.removeObject(forKey: key("lastSeen"))
        defaults.set(true, forKey: key("forgotten"))
        return connectionIDs
    }

    private func claim(_ fingerprint: String) {
        activeFingerprint = fingerprint
        pendingFingerprint = nil
        defaults.set(fingerprint, forKey: key("fingerprint"))
        defaults.set(false, forKey: key("forgotten"))
    }

    private func persistMetadata() {
        defaults.set(persistedDeviceID, forKey: key("deviceID"))
        defaults.set(persistedDisplayName, forKey: key("displayName"))
        if let persistedLastSeen {
            defaults.set(
                persistedLastSeen.timeIntervalSince1970,
                forKey: key("lastSeen")
            )
        }
    }

    private func key(_ suffix: String) -> String {
        "\(keyPrefix).\(suffix)"
    }

    private static func fingerprint(_ capability: String) -> String? {
        guard let normalized = normalized(capability) else { return nil }
        return SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum MobileLocalPairingStateStoreError: Error, Equatable, Sendable {
    case alreadyPaired
}
