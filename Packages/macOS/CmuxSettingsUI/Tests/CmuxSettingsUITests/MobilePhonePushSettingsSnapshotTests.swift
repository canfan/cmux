import Testing
@testable import CmuxSettingsUI

@Suite("MobilePhonePushSettingsSnapshot")
struct MobilePhonePushSettingsSnapshotTests {
    @Test func forwardingRequiresExplicitOptIn() {
        #expect(!MobilePhonePushSettingsSnapshot.defaultValue.forwardingEnabled)
    }
}
