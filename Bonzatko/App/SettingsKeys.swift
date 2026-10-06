import Foundation

/// Keys for user preferences (the settings window arrives in phase 5).
enum SettingsKeys {
    static let animationDuration = "animationDuration"
    static let defaultAnimationDuration = 2.0
    /// Export root folder; empty means `ExportPaths.defaultRoot`.
    static let exportRoot = "exportRoot"
}
