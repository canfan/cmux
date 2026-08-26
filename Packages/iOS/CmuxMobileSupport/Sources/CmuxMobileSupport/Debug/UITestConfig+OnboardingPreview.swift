#if DEBUG
import Foundation

/// Debug-only onboarding and scanner fixture flags.
public extension UITestConfig {
    /// Whether the deterministic onboarding preview is enabled.
    static var onboardingPreviewEnabled: Bool {
        UITestEnvironmentConfig(environment: ProcessInfo.processInfo.environment)
            .onboardingPreviewEnabled
    }

    /// Whether the onboarding preview should render its fallback connection state.
    static var onboardingConnectionFallbackEnabled: Bool {
        UITestEnvironmentConfig(environment: ProcessInfo.processInfo.environment)
            .onboardingConnectionFallbackEnabled
    }

    /// Whether the deterministic pairing-scanner preview is enabled.
    static var pairingScannerPreviewEnabled: Bool {
        UITestEnvironmentConfig(environment: ProcessInfo.processInfo.environment)
            .pairingScannerPreviewEnabled
    }

    /// Pairing code emitted when automation taps the scanner preview.
    static var pairingScannerCode: String? {
        UITestEnvironmentConfig(environment: ProcessInfo.processInfo.environment)
            .pairingScannerCode
    }
}
#endif
