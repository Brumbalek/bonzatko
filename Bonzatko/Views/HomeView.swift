import SwiftUI

/// Start screen: every class with "continue last lesson" and "new lesson".
struct HomeView: View {
    @Environment(ClassStore.self) private var store
    @Environment(Navigator.self) private var navigator

    var body: some View {
        let classes = store.classes.filter { !$0.isArchived }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Přehled")
                    .font(.largeTitle.bold())
                if classes.isEmpty {
                    ContentUnavailableView("Zatím žádné třídy", systemImage: "person.3",
                                           description: Text("Založte první třídu tlačítkem + vlevo nahoře."))
                        .padding(.top, 60)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    ForEach(classes) { ClassCard(schoolClass: $0) }
                }
            }
            .padding(24)
        }
        .navigationTitle("Přehled")
    }
}

private struct ClassCard: View {
    let schoolClass: SchoolClass
    @Environment(Navigator.self) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                navigator.sidebarSelection = .schoolClass(schoolClass.id)
            } label: {
                Text(schoolClass.name)
                    .font(.title3.bold())
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .help("Otevřít seznam studentů")

            Text(Czech.students(schoolClass.activeStudents.count))
                .foregroundStyle(.secondary)

            if let last = schoolClass.lastLesson {
                Text("Poslední Hodina: \(last.name)")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(last.createdAt.formatted(date: .long, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Zatím žádná Hodina")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            HStack {
                Button("Pokračovat v poslední Hodině") {
                    if let last = schoolClass.lastLesson {
                        navigator.openLesson = LessonRef(classID: schoolClass.id, lessonID: last.id)
                    }
                }
                .disabled(schoolClass.lastLesson == nil)

                NewLessonButton(schoolClass: schoolClass)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}

/// "Nová Hodina" – disabled for classes without active students.
/// Asks for confirmation only when an earlier lesson would be closed.
struct NewLessonButton: View {
    let schoolClass: SchoolClass
    @Environment(ClassStore.self) private var store
    @Environment(Navigator.self) private var navigator

    var body: some View {
        Button("Nová Hodina") {
            if schoolClass.lastLesson == nil {
                if let lessonID = store.createLesson(in: schoolClass.id) {
                    navigator.openLesson = LessonRef(classID: schoolClass.id, lessonID: lessonID)
                }
            } else {
                navigator.newLessonRequest = schoolClass.id
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(schoolClass.activeStudents.isEmpty || schoolClass.isArchived)
        .help(schoolClass.activeStudents.isEmpty ? "Nejdřív do třídy přidejte studenty." : "Založit novou Hodinu")
    }
}
