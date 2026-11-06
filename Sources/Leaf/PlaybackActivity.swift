import Foundation

/// Keep both the Mac and its display awake while a listening session is active. Each begin
/// has a matching end, including when the owning reader is released.
@MainActor
final class PlaybackActivity {
    private var token: NSObjectProtocol?
    var isActive: Bool { token != nil }

    func setActive(_ active: Bool) {
        if active {
            guard token == nil else { return }
            token = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                reason: "Leaf is playing narration")
        } else if let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }

    deinit {
        if let token { ProcessInfo.processInfo.endActivity(token) }
    }
}
