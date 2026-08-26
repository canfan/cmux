#if os(iOS)
/// Presentation state for the final onboarding scene.
///
/// Automatic discovery can search before showing recovery actions. Tailscale
/// pairing can act immediately from the idle or fallback state.
enum OnboardingConnectionPhase: Equatable, Sendable {
    case idle
    case searching
    case fallback
    case ready

    init(
        isMacReady: Bool,
        isSearching: Bool,
        didFinishSearch: Bool
    ) {
        if isMacReady {
            self = .ready
        } else if isSearching {
            self = .searching
        } else if !didFinishSearch {
            self = .idle
        } else {
            self = .fallback
        }
    }
}
#endif
