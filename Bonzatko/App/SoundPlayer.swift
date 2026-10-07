import AppKit

/// Quiet clicks while the wheel spins; the last click is simply where the wheel stops. Uses a built-in macOS sound.
@MainActor
final class SoundPlayer {
    private let defaults: UserDefaults
    /// Several copies so fast clicks can overlap (one NSSound cannot play twice at once).
    private let clicks: [NSSound]
    private var nextClick = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        clicks = (0..<6).compactMap { _ in
            let sound = NSSound(named: "Tink")?.copy() as? NSSound
            sound?.volume = 0.12
            return sound
        }
    }

    private var isEnabled: Bool {
        defaults.object(forKey: SettingsKeys.soundEnabled) as? Bool ?? true
    }

    func click() {
        guard isEnabled, !clicks.isEmpty else { return }
        let sound = clicks[nextClick % clicks.count]
        nextClick += 1
        sound.stop()
        sound.play()
    }
}
