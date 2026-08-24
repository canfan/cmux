import CMUXMobileCore
import Foundation
import Testing
@testable import CmuxMobileShell

@Suite
struct MobileAutomaticReconnectBackoffOwnerTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func preservesLongestDeadlineForSameAccount() {
        var owner = MobileAutomaticReconnectBackoffOwner()
        let first = owner.record(accountID: "account-a", retryAfterSeconds: 120, now: now)
        let shorter = owner.record(accountID: "account-a", retryAfterSeconds: 30, now: now)
        let blockedBeforeDeadline = owner.isBlocked(
            accountID: "account-a",
            now: now.addingTimeInterval(119)
        )
        let blockedAtDeadline = owner.isBlocked(
            accountID: "account-a",
            now: now.addingTimeInterval(120)
        )

        #expect(shorter == first)
        #expect(blockedBeforeDeadline)
        #expect(!blockedAtDeadline)
    }

    @Test
    func accountBoundaryDoesNotApplyAnotherAccountsDeadline() {
        var owner = MobileAutomaticReconnectBackoffOwner()
        _ = owner.record(accountID: "account-a", retryAfterSeconds: 120, now: now)
        let otherAccountBlocked = owner.isBlocked(accountID: "account-b", now: now)
        let owningAccountBlocked = owner.isBlocked(accountID: "account-a", now: now)

        #expect(!otherAccountBlocked)
        #expect(owningAccountBlocked)
    }

    @Test
    func normalizesInvalidDelayWithoutShorteningValidServerAuthority() {
        var owner = MobileAutomaticReconnectBackoffOwner()
        let minimum = owner.record(accountID: "account-a", retryAfterSeconds: 0, now: now)
        owner.clear()
        let fullDay = owner.record(accountID: "account-a", retryAfterSeconds: 86_400, now: now)

        #expect(minimum == now.addingTimeInterval(1))
        #expect(fullDay == now.addingTimeInterval(86_400))
    }

    @Test
    func transientFailuresBackOffExponentiallyAndKeepServerAuthority() {
        var owner = MobileAutomaticReconnectBackoffOwner()
        let serverDeadline = owner.record(
            accountID: "account-a",
            retryAfterSeconds: 120,
            now: now
        )
        var transientDeadlines: [Date] = []
        for offset in 0 ..< 7 {
            transientDeadlines.append(owner.recordTransientFailure(
                accountID: "account-a",
                now: now.addingTimeInterval(TimeInterval(offset))
            ))
        }

        #expect(transientDeadlines == Array(repeating: serverDeadline, count: 7))
        #expect(owner.transientFailureCount == 7)
        #expect(owner.retryAt == serverDeadline)
    }

    @Test
    func transientBackoffProgressesToSixtySecondsWithoutResettingAtDeadline() {
        var owner = MobileAutomaticReconnectBackoffOwner()
        let expectedDelays: [TimeInterval] = [2, 4, 8, 16, 32, 60, 60]

        for (index, expectedDelay) in expectedDelays.enumerated() {
            let failureTime = now.addingTimeInterval(TimeInterval(index * 100))
            let deadline = owner.recordTransientFailure(
                accountID: "account-a",
                now: failureTime
            )
            let blockedBeforeDeadline = owner.isBlocked(
                accountID: "account-a",
                now: deadline.addingTimeInterval(-1)
            )
            let blockedAtDeadline = owner.isBlocked(
                accountID: "account-a",
                now: deadline
            )
            #expect(deadline == failureTime.addingTimeInterval(expectedDelay))
            #expect(blockedBeforeDeadline)
            #expect(!blockedAtDeadline)
        }

        #expect(owner.transientFailureCount == expectedDelays.count)
    }

    @Test
    func clearingTransientCooldownPreservesServerFloorAndFailureCount() {
        var owner = MobileAutomaticReconnectBackoffOwner()
        let serverDeadline = owner.record(
            accountID: "account-a",
            retryAfterSeconds: 120,
            now: now
        )
        _ = owner.recordTransientFailure(accountID: "account-a", now: now)

        owner.clearTransientCooldown(accountID: "account-a")

        let stillBlocked = owner.isBlocked(
            accountID: "account-a",
            now: now.addingTimeInterval(119)
        )
        #expect(owner.retryAt == serverDeadline)
        #expect(owner.transientFailureCount == 1)
        #expect(stillBlocked)
    }

    @Test
    func successfulConnectionResetsAllBackoffForOnlyItsAccount() {
        var owner = MobileAutomaticReconnectBackoffOwner()
        _ = owner.recordTransientFailure(accountID: "account-a", now: now)

        owner.clear(accountID: "account-b")
        #expect(owner.accountID == "account-a")
        #expect(owner.transientFailureCount == 1)

        owner.clear(accountID: "account-a")
        #expect(owner.accountID == nil)
        #expect(owner.retryAt == nil)
        #expect(owner.transientFailureCount == 0)
    }

    @MainActor
    @Test
    func foregroundRecoveryClearsTransientCooldown() async throws {
        let (pairedStore, directory) = try ReconnectRouteSelectionTests()
            .makePairedMacStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MobileShellComposite(
            isSignedIn: true,
            pairedMacStore: pairedStore,
            identityProvider: StaticIdentityProvider(userID: "account-a"),
            reachability: AlwaysOnlineReachability(),
            pairingHintDefaults: UserDefaults(
                suiteName: "foreground-backoff-\(UUID().uuidString)"
            )!
        )
        store.recordTransientAutomaticReconnectBackoff(accountID: "account-a")
        #expect(store.automaticReconnectBackoffOwner.transientRetryAt != nil)

        store.recoverMobileConnection(trigger: .foreground)

        #expect(store.automaticReconnectBackoffOwner.transientRetryAt == nil)
        store.connectionRecoveryOwner.cancel()
    }

    @MainActor
    @Test
    func accountFreeLocalPairingFailureSchedulesAutomaticRetry() throws {
        let suiteName = "local-pairing-backoff-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let route = try CmxAttachRoute(
            id: "tailscale",
            kind: .tailscale,
            endpoint: .hostPort(host: "100.64.0.5", port: 58465),
            priority: 10
        )
        let ticket = try CmxAttachTicket(
            workspaceID: "workspace-1",
            terminalID: "terminal-1",
            macDeviceID: "mac-1",
            macDisplayName: "Studio",
            routes: [route],
            authToken: "local-capability",
            localPairing: true
        )
        let store = MobileShellComposite(
            isSignedIn: false,
            reachability: AlwaysOnlineReachability(),
            pairingHintDefaults: defaults
        )
        store.localPairingRecoveryTicket = ticket

        store.armAutomaticReconnectRetryAfterFailedAttempt(
            failure: .connectionRefused,
            stackUserID: nil
        )

        #expect(store.automaticReconnectBackoffOwner.transientFailureCount == 1)
        #expect(store.automaticReconnectRetryTask != nil)
        store.clearAutomaticReconnectBackoff()
    }

    @MainActor
    @Test
    func persistedLocalPairingRestoresRecoveryAuthorityBeforeDial() throws {
        let route = try CmxAttachRoute(
            id: "tailscale",
            kind: .tailscale,
            endpoint: .hostPort(host: "100.64.0.5", port: 58465),
            priority: 10
        )
        let ticket = try CmxAttachTicket(
            workspaceID: "workspace-1",
            terminalID: "terminal-1",
            macDeviceID: "mac-1",
            macDisplayName: "Studio",
            routes: [route],
            authToken: "local-capability",
            localPairing: true
        )
        let pairingURL = try #require(CmxPairingQRCode().encode(
            ticket,
            routeDisclosureMode: .localTailscalePairing,
            pairingURLScheme: CmxPairingURLScheme(rawValue: CmxPairingURLScheme.release)
        ))
        let store = MobileShellComposite()

        #expect(store.restorePersistedLocalPairingAuthority(from: pairingURL))
        #expect(store.localPairingRecoveryTicket == ticket)
        #expect(store.hasDurableConnectionRecoveryAuthority)
    }
}
