import AppKit
import CMUXMobileCore
import SwiftUI

extension MobilePairingView {
    @ViewBuilder
    func pairedContent(_ device: MobileLocalPairingDeviceSnapshot) -> some View {
        VStack(spacing: 12) {
            Image(systemName: device.isConnected ? "iphone.radiowaves.left.and.right" : "iphone")
                .cmuxFont(size: 36)
                .foregroundStyle(device.isConnected ? Color.green : Color.secondary)
            Text(device.displayName)
                .cmuxFont(.title3, weight: .semibold)
            Text(String(
                localized: "mobile.pairing.paired.title",
                defaultValue: "Paired with this Mac"
            ))
                .foregroundStyle(.secondary)
            if device.isConnected {
                Text(String(
                    localized: "mobile.pairing.paired.connected",
                    defaultValue: "Connected over Tailscale"
                ))
                    .cmuxFont(.callout)
                    .foregroundStyle(.green)
            } else if let lastSeen = device.lastSeen {
                Text(String(
                    format: String(
                        localized: "mobile.pairing.paired.lastSeen",
                        defaultValue: "Offline · Last seen %@"
                    ),
                    locale: .current,
                    lastSeen.formatted(.relative(presentation: .named))
                ))
                    .cmuxFont(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(
                    localized: "mobile.pairing.paired.offline",
                    defaultValue: "Offline"
                ))
                    .cmuxFont(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(String(
                localized: "mobile.pairing.paired.oneDevice",
                defaultValue: "Local pairing is limited to one iPhone. Forget this device before pairing another."
            ))
                .cmuxFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(
                String(
                    localized: "mobile.pairing.paired.forget",
                    defaultValue: "Disconnect and Forget"
                ),
                role: .destructive
            ) {
                Task { await model.forgetLocalPairingDevice() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    @ViewBuilder
    var connectedContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .cmuxFont(size: 36)
                .foregroundStyle(.green)
            Text(String(localized: "mobile.pairing.connected.title", defaultValue: "iPhone connected"))
                .cmuxFont(.title3, weight: .semibold)
            Text(String(localized: "mobile.pairing.connected.subtitle", defaultValue: "Your terminal workspaces are now syncing to your iPhone. You can close this window."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    func copyButton(label: String, value: String) -> some View {
        Button {
            guard GhosttyApp.terminalPasteboard.writeString(
                value,
                to: .general
            ) else { return }
            flashCopied(value)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copiedValue == value ? "checkmark" : "doc.on.doc")
                Text(copiedValue == value
                    ? String(localized: "mobile.pairing.manual.copied", defaultValue: "Copied")
                    : label)
            }
            .cmuxFont(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    func flashCopied(_ value: String) {
        copiedValueGeneration &+= 1
        let generation = copiedValueGeneration
        copiedValue = value
        Task { @MainActor in
            try? await ContinuousClock().sleep(for: .seconds(1.6))
            guard copiedValueGeneration == generation else { return }
            copiedValue = nil
        }
    }

    func centered<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) { content() }
            .frame(maxWidth: .infinity, minHeight: 200)
    }
}
