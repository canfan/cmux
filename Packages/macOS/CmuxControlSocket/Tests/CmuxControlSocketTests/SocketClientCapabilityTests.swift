@testable import CmuxControlSocket
import Foundation
import Testing

@Suite("Socket client capabilities")
struct SocketClientCapabilityTests {
    private let secret = Data(
        repeating: 0x3C,
        count: SocketClientCapabilityAuthority.secureByteCount
    )
    private let nonce = Data(
        repeating: 0xC3,
        count: SocketClientCapabilityAuthority.secureByteCount
    )

    @Test func authorityRecreationPreservesIssuedCapabilities() {
        let original = SocketClientCapabilityAuthority(
            secret: secret,
            audience: "com.cmuxterm.test"
        )
        let recreated = SocketClientCapabilityAuthority(
            secret: secret,
            audience: "com.cmuxterm.test"
        )
        let capability = original.issueCapability(nonce: nonce)

        #expect(recreated.verifies(capability))
    }

    @Test func audienceAndSignatureAreBound() {
        let issuer = SocketClientCapabilityAuthority(
            secret: secret,
            audience: "com.cmuxterm.test"
        )
        let otherAudience = SocketClientCapabilityAuthority(
            secret: secret,
            audience: "com.cmuxterm.other"
        )
        let capability = issuer.issueCapability(nonce: nonce)
        let tampered = capability.dropLast() + (capability.last == "A" ? "B" : "A")

        #expect(!otherAudience.verifies(capability))
        #expect(!issuer.verifies(String(tampered)))
    }

    @Test func explicitBindingCannotBeReplayedInAnotherContext() {
        let issuer = SocketClientCapabilityAuthority(
            secret: secret,
            audience: "com.cmuxterm.test"
        )
        let originalBinding = Data("tailscale:100.64.0.5:58465".utf8)
        let otherBinding = Data("tailscale:100.64.0.6:58465".utf8)
        let capability = issuer.issueCapability(
            binding: originalBinding,
            nonce: nonce
        )

        #expect(issuer.verifies(capability, binding: originalBinding))
        #expect(!issuer.verifies(capability, binding: otherBinding))
        #expect(!issuer.verifies(capability))
    }

    @Test func envelopeRoundTripsWithoutExposingCapabilityToDispatch() throws {
        let issuer = SocketClientCapabilityAuthority(
            secret: secret,
            audience: "com.cmuxterm.test"
        )
        let capability = issuer.issueCapability(nonce: nonce)
        let envelope = try #require(SocketClientCapabilityEnvelope(capability: capability))
        let command = "hooks claude prompt-submit"

        let parsed = try #require(SocketClientCapabilityCommand(envelope.wrap(command)))
        #expect(parsed.capability == capability)
        #expect(parsed.command == command)
    }

    @Test func secretStoreReusesPersistentSecret() {
        let store = SocketClientCapabilitySecretStore(
            loadSecret: { secret },
            saveSecret: { _ in
                Issue.record("Existing valid secrets must not be rewritten")
                return false
            },
            randomData: { _ in Data() }
        )

        #expect(store.loadOrCreateSecret() == secret)
    }

    @Test func secretStorePersistsNewSecret() {
        let generated = Data(
            repeating: 0x7E,
            count: SocketClientCapabilityAuthority.secureByteCount
        )
        let store = SocketClientCapabilitySecretStore(
            loadSecret: { nil },
            saveSecret: {
                #expect($0 == generated)
                return true
            },
            randomData: { count in
                #expect(count == SocketClientCapabilityAuthority.secureByteCount)
                return generated
            }
        )

        #expect(store.loadOrCreateSecret() == generated)
    }

    @Test func fileSecretStoreSurvivesAdHocBuildRestarts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("mobile-local-pairing.secret")
        let generated = Data(
            repeating: 0x5A,
            count: SocketClientCapabilityAuthority.secureByteCount
        )
        let first = SocketClientCapabilityFileSecretStore(
            fileURL: fileURL,
            randomData: { count in
                #expect(count == SocketClientCapabilityAuthority.secureByteCount)
                return generated
            }
        )

        #expect(first.loadOrCreateSecret() == generated)

        let recreated = SocketClientCapabilityFileSecretStore(
            fileURL: fileURL,
            randomData: { _ in
                Issue.record("A persisted file secret must be reused")
                return Data()
            }
        )
        #expect(recreated.loadOrCreateSecret() == generated)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test func fileSecretStoreRejectsSymlinkTargets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appendingPathComponent("target")
        let fileURL = directory.appendingPathComponent("mobile-local-pairing.secret")
        try Data(repeating: 0x44, count: SocketClientCapabilityAuthority.secureByteCount)
            .write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: targetURL)
        let generated = Data(
            repeating: 0x6B,
            count: SocketClientCapabilityAuthority.secureByteCount
        )
        let store = SocketClientCapabilityFileSecretStore(
            fileURL: fileURL,
            randomData: { _ in generated }
        )

        #expect(store.loadOrCreateSecret() == generated)
        #expect(try Data(contentsOf: targetURL) != generated)
    }
}
