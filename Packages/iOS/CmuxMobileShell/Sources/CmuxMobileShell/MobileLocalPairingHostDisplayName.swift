import Foundation

/// Resolves the authenticated host label shown for a local Tailscale pairing.
struct MobileLocalPairingHostDisplayName: Sendable {
    let value: String?

    init(
        macDisplayName: String?,
        tailscaleDNSName: String?,
        isLocalPairing: Bool
    ) {
        let fallback = Self.nonempty(macDisplayName)
        guard isLocalPairing,
              let dnsName = Self.normalizedTailscaleDNSName(tailscaleDNSName),
              let firstLabel = dnsName.split(separator: ".", maxSplits: 1).first,
              !firstLabel.isEmpty else {
            value = fallback
            return
        }
        value = String(firstLabel)
    }

    static func resolve(
        macDisplayName: String?,
        tailscaleDNSName: String?,
        isLocalPairing: Bool
    ) -> String? {
        Self(
            macDisplayName: macDisplayName,
            tailscaleDNSName: tailscaleDNSName,
            isLocalPairing: isLocalPairing
        ).value
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func normalizedTailscaleDNSName(_ value: String?) -> String? {
        guard let trimmed = nonempty(value) else { return nil }
        let normalized = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
        let lowercased = normalized.lowercased()
        guard lowercased.hasSuffix(".ts.net"), lowercased.count <= 253 else { return nil }
        let labels = lowercased.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 3 else { return nil }
        for label in labels {
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-",
                  label.last != "-",
                  label.utf8.allSatisfy({ byte in
                      (byte >= 0x61 && byte <= 0x7A)
                          || (byte >= 0x30 && byte <= 0x39)
                          || byte == 0x2D
                  }) else {
                return nil
            }
        }
        return lowercased
    }
}
