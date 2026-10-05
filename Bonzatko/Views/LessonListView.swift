import SwiftUI

/// All lessons of a class, newest first. Only the last one is open.
struct LessonListView: View {
    let schoolClass: SchoolClass
    @Environment(ClassStore.self) private var store
    @Environment(Navigator.self) private var navigator

    var body: some View {
        List {
            if schoolClass.lessons.isEmpty {
                Text("Třída zatím nemá žádnou Hodinu. Založte ji tlačítkem Nová Hodina.")
                    .foregroundStyle(.secondary)
            }
            ForEach(schoolClass.lessons.reversed()) { lesson in
                row(lesson)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func row(_ lesson: Lesson) -> some View {
        let ref = LessonRef(classID: schoolClass.id, lessonID: lesson.id)
        let isOpen = schoolClass.isOpen(lesson.id)
        let isLast = schoolClass.isLast(lesson.id) && !schoolClass.isArchived

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name)
                    .fontWeight(isOpen ? .semibold : .regular)
                Text("\(lesson.createdAt.formatted(date: .long, time: .shortened)) · vylosováno \(lesson.draws.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LessonStatusBadge(isOpen: isOpen)

            if isOpen && isLast {
                Button("Pokračovat") { navigator.openLesson = ref }
            } else {
                Button("Prohlédnout") { navigator.browsedLesson = ref }
            }
            if isLast {
                Menu("Další akce", systemImage: "ellipsis.circle") {
                    if isOpen {
                        Button("Přejmenovat…", systemImage: "pencil") { navigator.lessonRenameRequest = ref }
                        Button("Uzavřít Hodinu", systemImage: "lock") { store.closeLastLesson(in: schoolClass.id) }
                    } else {
                        Button("Znovu otevřít", systemImage: "lock.open") { store.reopenLastLesson(in: schoolClass.id) }
                    }
                    Divider()
                    Button("Smazat…", systemImage: "trash", role: .destructive) { navigator.lessonDeletionRequest = ref }
                }
                .menuStyle(.button)
                .labelStyle(.iconOnly)
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }
}

struct LessonStatusBadge: View {
    let isOpen: Bool

    var body: some View {
        Text(isOpen ? "Otevřená" : "Uzavřená")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(isOpen ? .green : .secondary)
            .background((isOpen ? Color.green : Color.secondary).opacity(0.15), in: .capsule)
    }
}

/// Read-only list of who was drawn in a lesson and with what result.
struct LessonBrowserSheet: View {
    let ref: LessonRef
    @Environment(ClassStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let schoolClass = store.schoolClass(ref.classID)
        let lesson = schoolClass?.lessons.first { $0.id == ref.lessonID }

        VStack(alignment: .leading, spacing: 12) {
            if let schoolClass, let lesson {
                HStack(alignment: .firstTextBaseline) {
                    Text(lesson.name)
                        .font(.title2.bold())
                    Spacer()
                    LessonStatusBadge(isOpen: schoolClass.isOpen(lesson.id))
                }
                Text(lesson.createdAt.formatted(date: .complete, time: .shortened))
                    .foregroundStyle(.secondary)

                DrawResultsList(schoolClass: schoolClass, lesson: lesson)
            }
            HStack {
                Spacer()
                Button("Zavřít") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 460)
    }
}

/// Drawn students of a lesson in draw order, with their results.
struct DrawResultsList: View {
    let schoolClass: SchoolClass
    let lesson: Lesson

    var body: some View {
        List {
            if lesson.draws.isEmpty {
                Text("V této Hodině zatím nebyl nikdo vylosován.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(lesson.draws.enumerated()), id: \.element.id) { index, draw in
                HStack {
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                    Text(studentName(draw.studentID))
                    Spacer()
                    Text(draw.result.label)
                        .foregroundStyle(draw.result.color)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func studentName(_ id: UUID) -> String {
        guard let student = schoolClass.student(id) else { return "Neznámý student" }
        return student.isActive ? student.name : "\(student.name) (odebrán)"
    }
}

extension DrawResult {
    var label: String {
        switch self {
        case .pending: "čeká na výsledek"
        case .present: "přítomen"
        case .absent: "nepřítomen"
        case .skipped: "nezaznamenáno"
        }
    }

    var color: Color {
        switch self {
        case .present: .blue
        case .absent: .red
        case .pending, .skipped: .secondary
        }
    }
}

/// Renames the open lesson; shows why a name cannot be used.
struct RenameLessonSheet: View {
    let ref: LessonRef
    @Environment(ClassStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Přejmenovat Hodinu")
                .font(.title2.bold())
            TextField("Název Hodiny", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Zrušit", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Uložit", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            name = store.schoolClass(ref.classID)?.lessons.first { $0.id == ref.lessonID }?.name ?? ""
        }
    }

    private func save() {
        error = store.renameLesson(ref.lessonID, to: name, in: ref.classID)
        if error == nil { dismiss() }
    }
}
