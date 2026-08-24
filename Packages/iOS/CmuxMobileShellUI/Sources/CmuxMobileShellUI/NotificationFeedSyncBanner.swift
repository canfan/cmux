#if os(iOS)
import CmuxMobileSupport
import SwiftUI

/// Explains that the in-app feed and optional cloud push are separate paths.
struct NotificationFeedSyncBanner: View {
    let syncsOverTailscale: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(L10n.string(
                    "mobile.notificationFeed.sync.body",
                    defaultValue: "This feed syncs directly from your Mac. Background push alerts are separate and optional."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("MobileNotificationFeedSyncBanner")
    }

    private var title: String {
        if syncsOverTailscale {
            return L10n.string(
                "mobile.notificationFeed.sync.tailscale",
                defaultValue: "Live over Tailscale"
            )
        }
        return L10n.string(
            "mobile.notificationFeed.sync.direct",
            defaultValue: "Live from paired Macs"
        )
    }
}
#endif
