import Foundation
import Observation

struct LessonRef: Hashable, Identifiable, Sendable {
    let classID: UUID
    let lessonID: UUID

    var id: Self { self }
}

enum SidebarItem: Hashable, Sendable {
    case home
    case schoolClass(UUID)
}

/// Which screen is shown, plus requests that need a confirmation dialog at the window level.
@MainActor
@Observable
final class Navigator {
    var sidebarSelection: SidebarItem? = .home
    /// The lesson shown full-window (drawing screen).
    var openLesson: LessonRef?
    /// A closed lesson shown read-only.
    var browsedLesson: LessonRef?

    /// Set when the user asked for a new lesson; the window asks for confirmation first.
    var newLessonRequest: UUID?
    var lessonDeletionRequest: LessonRef?
    var lessonRenameRequest: LessonRef?
}
