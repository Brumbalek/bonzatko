import SwiftUI

/// Full-window screen of the open lesson. The drawing itself arrives in phase 3.
struct LessonView: View {
    let ref: LessonRef
    @Environment(ClassStore.self) private var store
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if let schoolClass = store.schoolClass(ref.classID),
           let lesson = schoolClass.lessons.first(where: { $0.id == ref.lessonID }) {
            content(schoolClass, lesson)
        } else {
            ContentUnavailableView("Hodina neexistuje", systemImage: "questionmark.circle")
                .onAppear { navigator.openLesson = nil }
        }
    }

    private func content(_ schoolClass: SchoolClass, _ lesson: Lesson) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Třídy", systemImage: "chevron.left") { navigator.openLesson = nil }
                    .help("Zpět na přehled tříd")
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.name)
                        .font(.headline)
                    Text(schoolClass.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Přejmenovat", systemImage: "pencil") { navigator.lessonRenameRequest = ref }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Přejmenovat Hodinu")
                Spacer()
            }
            .padding(12)

            Divider()

            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 12) {
                    Image(systemName: "dial.medium")
                        .font(.system(size: 64))
                        .foregroundStyle(.tertiary)
                    Text("Tady bude losování (fáze 3).")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("Vylosováno \(lesson.draws.count) / \(schoolClass.activeStudents.count)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
    }
}
