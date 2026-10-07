import Foundation

/// Keys for user preferences.
enum SettingsKeys {
    static let animationDuration = "animationDuration"
    static let defaultAnimationDuration = 2.0
    static let animationDurationRange = 0.5...6.0
    /// Export root folder; empty means `ExportPaths.defaultRoot`.
    static let exportRoot = "exportRoot"
    static let soundEnabled = "soundEnabled"
}
