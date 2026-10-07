import SwiftUI

/// Full-window drawing screen of the open lesson.
struct LessonView: View {
    let ref: LessonRef
    @Environment(ClassStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(SyncFlow.self) private var flow
    @AppStorage(SettingsKeys.animationDuration) private var animationDuration = SettingsKeys.defaultAnimationDuration
    @AppStorage(SettingsKeys.soundEnabled) private var soundEnabled = true
    @State private var sound = SoundPlayer()

    @State private var keyMonitor = KeyMonitor()
    @State private var spinTask: Task<Void, Never>?
    @State private var spinningName: String?
    @State private var showsPoolEmpty = false
    @State private var showsResultHint = false
    @State private var hintTask: Task<Void, Never>?
    @State private var showsCorrections = false

    private var isSpinning: Bool { spinningName != nil }

    var body: some View {
        if let schoolClass = store.schoolClass(ref.classID),
           let lesson = schoolClass.lessons.first(where: { $0.id == ref.lessonID }),
           schoolClass.isOpen(lesson.id) {
            content(schoolClass, lesson)
                .onAppear { keyMonitor.start(handleKey) }
                .onDisappear {
                    keyMonitor.stop()
                    spinTask?.cancel()
                }
        } else {
            ContentUnavailableView("Hodina je uzavřená", systemImage: "lock")
                .onAppear { navigator.openLesson = nil }
        }
    }

    // MARK: Layout

    private func content(_ schoolClass: SchoolClass, _ lesson: Lesson) -> some View {
        VStack(spacing: 0) {
            topBar(schoolClass, lesson)
            Divider()
            stage(schoolClass, lesson)
            Divider()
            bottomBar(schoolClass, lesson)
        }
        .inspector(isPresented: $showsCorrections) {
            CorrectionPanel(classID: ref.classID, lesson: lesson, schoolClass: schoolClass)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
    }

    private func topBar(_ schoolClass: SchoolClass, _ lesson: Lesson) -> some View {
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
            Toggle(isOn: $soundEnabled) {
                Label(soundEnabled ? "Zvuk zapnutý" : "Zvuk vypnutý",
                      systemImage: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .controlSize(.large)
            .help(soundEnabled ? "Vypnout zvuk" : "Zapnout zvuk")
            SettingsButton()
                .controlSize(.large)
            Button("Uzavřít Hodinu", systemImage: "lock") {
                spinTask?.cancel()
                flow.close(ref)
            }
            .controlSize(.large)
            .disabled(isSpinning)
            .help("Uzavřít Hodinu a uložit ji do Excelu. Dokud nezaložíte novou, půjde znovu otevřít.")
            Toggle(isOn: $showsCorrections) {
                Label("Opravit výsledky", systemImage: "list.bullet.clipboard")
            }
            .toggleStyle(.button)
            .controlSize(.large)
            .help("Zobrazit vylosované v této Hodině a opravit jejich stav")
        }
        .padding(12)
    }

    private func stage(_ schoolClass: SchoolClass, _ lesson: Lesson) -> some View {
        GeometryReader { geometry in
            let fontSize = min(geometry.size.width / 9, geometry.size.height / 3.2)
            ZStack {
                if let spinningName {
                    bigName(spinningName, color: .primary, size: fontSize)
                } else if showsPoolEmpty {
                    Text("V této Hodině už byli vylosováni všichni.")
                        .font(.system(size: fontSize * 0.45, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else if let draw = lesson.draws.last, let student = schoolClass.student(draw.studentID) {
                    bigName(student.name, color: displayColor(draw.result), size: fontSize)
                } else {
                    Text("Stiskněte mezerník")
                        .font(.system(size: fontSize * 0.45, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                if showsResultHint {
                    VStack {
                        Spacer()
                        Text("Nejdřív označte výsledek")
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: .capsule)
                            .padding(.bottom, 32)
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func bigName(_ name: String, color: Color, size: CGFloat) -> some View {
        Text(name)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.3)
            .padding(.horizontal, 40)
    }

    private func bottomBar(_ schoolClass: SchoolClass, _ lesson: Lesson) -> some View {
        let pending = lesson.draws.last?.result == .pending
        return HStack(spacing: 12) {
            Button("Losovat (mezerník)", systemImage: "dial.medium") { handle(.space) }
                .buttonStyle(.borderedProminent)
                .disabled(isSpinning)
            Button("Zpět (⌫ / ⌘Z)", systemImage: "arrow.uturn.backward") { handle(.undo) }
                .disabled(isSpinning || lesson.draws.isEmpty)
                .help("Vrátit poslední rozhodnutí")

            if pending && !isSpinning {
                Text("↑ přítomen   ↓ nepřítomen   ← → nezaznamenat")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Vylosováno \(lesson.draws.count) / \(schoolClass.activeStudents.count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .controlSize(.large)
        .padding(12)
    }

    private func displayColor(_ result: DrawResult) -> Color {
        switch result {
        case .present: .blue
        case .absent: .red
        case .pending, .skipped: .primary
        }
    }

    // MARK: Keys and actions

    private func handleKey(_ key: DrawKey, _ window: NSWindow?) -> Bool {
        if key == .fullScreen {
            window?.toggleFullScreen(nil)
            return true
        }
        handle(key)
        return true
    }

    private func handle(_ key: DrawKey) {
        guard !isSpinning else { return } // everything waits until the wheel stops
        switch key {
        case .space: startDraw()
        case .up: store.recordResult(.present, in: ref.classID)
        case .down: store.recordResult(.absent, in: ref.classID)
        case .left, .right: store.recordResult(.skipped, in: ref.classID)
        case .undo:
            store.undoLastStep(in: ref.classID)
            showsPoolEmpty = false
        case .fullScreen: break
        }
    }

    private func startDraw() {
        guard let schoolClass = store.schoolClass(ref.classID), let lesson = schoolClass.lastLesson else { return }
        let pool = DrawEngine.pool(for: schoolClass, lesson: lesson)

        switch store.drawNext(in: ref.classID) {
        case .drawn(let winner):
            showsPoolEmpty = false
            spin(pool: pool, winner: winner)
        case .needsResult:
            flashResultHint()
        case .poolEmpty:
            showsPoolEmpty = true
        case .notAllowed:
            break
        }
    }

    private func spin(pool: [Student], winner: Student) {
        let duration = max(animationDuration, 0)
        guard duration > 0, pool.count > 1 else {
            sound.click()
            return
        }
        let times = DrawEngine.tickTimes(duration: duration)
        var generator = SystemRandomNumberGenerator()
        let names = DrawEngine.spinSequence(pool: pool, winner: winner, length: times.count, using: &generator)

        spinningName = names.first
        spinTask = Task {
            let start = ContinuousClock.now
            for (time, name) in zip(times, names) {
                try? await Task.sleep(until: start + .seconds(time), clock: .continuous)
                if Task.isCancelled { break }
                spinningName = name
                sound.click()
            }
            spinningName = nil
        }
    }

    private func flashResultHint() {
        hintTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { showsResultHint = true }
        hintTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { showsResultHint = false }
        }
    }
}

/// "Opravit výsledky": every draw of this lesson with a switch for its result.
private struct CorrectionPanel: View {
    let classID: UUID
    let lesson: Lesson
    let schoolClass: SchoolClass
    @Environment(ClassStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vylosovaní v této Hodině")
                .font(.headline)
                .padding([.horizontal, .top])
            List {
                if lesson.draws.isEmpty {
                    Text("Zatím nikdo nebyl vylosován.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(lesson.draws.enumerated()), id: \.element.id) { index, draw in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(index + 1). \(schoolClass.student(draw.studentID)?.name ?? "Neznámý student")")
                            if draw.result == .pending {
                                Spacer()
                                Text("čeká na šipku")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // Always the same three segments; a name waiting for an arrow shows none selected.
                        Picker("Stav", selection: Binding<DrawResult?>(
                            get: { draw.result == .pending ? nil : draw.result },
                            set: { if let result = $0 { store.correctResult(of: draw.id, to: result, in: classID) } }
                        )) {
                            Text("přítomen").tag(DrawResult?.some(.present))
                            Text("nepřítomen").tag(DrawResult?.some(.absent))
                            Text("nezaznamenáno").tag(DrawResult?.some(.skipped))
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
