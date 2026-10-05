import Foundation
import Testing
@testable import Bonzatko

/// Deterministic generator so statistical tests always give the same result.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct DrawEngineTests {
    @Test func weightHalvesWithEveryRecordedDraw() {
        #expect(DrawEngine.weight(drawCount: 0) == 1)
        #expect(DrawEngine.weight(drawCount: 1) == 0.5)
        #expect(DrawEngine.weight(drawCount: 3) == 0.125)
    }

    @Test func poolExcludesEveryoneDrawnInThisLessonAndRemovedStudents() {
        let a = Student(name: "Adam Bílý"), b = Student(name: "Bára Černá"), c = Student(name: "Cyril Dub")
        let d = Student(name: "Dana Eliášová"), removed = Student(name: "Emil Fiala", removedAt: .now)
        let lesson = Lesson(name: "L", draws: [
            Draw(studentID: a.id, result: .present),
            Draw(studentID: b.id, result: .skipped),
            Draw(studentID: c.id, result: .pending),
        ])
        let schoolClass = SchoolClass(name: "Třída", students: [a, b, c, d, removed], lessons: [lesson])
        #expect(DrawEngine.pool(for: schoolClass, lesson: lesson).map(\.id) == [d.id])
    }

    @Test func onlyRecordedDrawsAndVirtualCountLowerTheWeight() {
        let a = Student(name: "Adam Bílý")
        let b = Student(name: "Bára Černá")
        let late = Student(name: "Cyril Dub", virtualDrawCount: 2)
        let old = Lesson(name: "L1", draws: [
            Draw(studentID: a.id, result: .present),
            Draw(studentID: b.id, result: .skipped),
        ])
        let current = Lesson(name: "L2")
        let schoolClass = SchoolClass(name: "Třída", students: [a, b, late], lessons: [old, current])
        let weights = Dictionary(uniqueKeysWithValues: DrawEngine.weightedPool(for: schoolClass, lesson: current).map { ($0.student.id, $0.weight) })
        #expect(weights[a.id] == 0.5)
        #expect(weights[b.id] == 1) // skipped does not count
        #expect(weights[late.id] == 0.25) // virtual count only
    }

    @Test func pickFollowsWeightsStatistically() {
        let fresh = Student(name: "Nový"), once = Student(name: "Jednou"), twice = Student(name: "Dvakrát")
        let candidates = [(student: fresh, weight: 1.0), (student: once, weight: 0.5), (student: twice, weight: 0.25)]
        var generator = SeededGenerator(seed: 42)
        var counts: [UUID: Int] = [:]
        let rounds = 70_000
        for _ in 0..<rounds {
            let picked = DrawEngine.pick(from: candidates, using: &generator)!
            counts[picked.id, default: 0] += 1
        }
        // Expected shares: 4/7, 2/7, 1/7.
        #expect(abs(Double(counts[fresh.id]!) / Double(rounds) - 4.0 / 7) < 0.01)
        #expect(abs(Double(counts[once.id]!) / Double(rounds) - 2.0 / 7) < 0.01)
        #expect(abs(Double(counts[twice.id]!) / Double(rounds) - 1.0 / 7) < 0.01)
    }

    @Test func pickFromEmptyPoolReturnsNil() {
        var generator = SeededGenerator(seed: 1)
        #expect(DrawEngine.pick(from: [], using: &generator) == nil)
    }

    @Test func animationSlowsDownAndEndsOnTime() {
        let times = DrawEngine.tickTimes(duration: 2)
        #expect(times.count == 28)
        #expect(abs(times.last! - 2) < 0.000_1)
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        #expect(gaps.first! < 0.05)
        #expect(zip(gaps.dropFirst(), gaps).allSatisfy { $0 >= $1 })
    }

    @Test func spinSequenceEndsOnWinnerWithoutRepeats() {
        let pool = ["Adam", "Bára", "Cyril"].map { Student(name: $0) }
        var generator = SeededGenerator(seed: 7)
        let names = DrawEngine.spinSequence(pool: pool, winner: pool[1], length: 30, using: &generator)
        #expect(names.count == 30)
        #expect(names.last == "Bára")
        #expect(zip(names.dropFirst(), names).allSatisfy { $0 != $1 })
    }
}

@MainActor
struct DrawingStoreTests {
    private func makeStore(names: [String]) -> (ClassStore, UUID) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BonzatkoTests-\(UUID())")
        let store = ClassStore(repository: ClassRepository(directory: directory) { try FileManager.default.removeItem(at: $0) })
        let classID = store.createClass(name: "Úvod do marketingu", abbreviation: "UDM")
        store.addStudents(names, to: classID)
        store.createLesson(in: classID)
        return (store, classID)
    }

    private func lastDraws(_ store: ClassStore, _ classID: UUID) -> [Draw] {
        store.schoolClass(classID)?.lastLesson?.draws ?? []
    }

    @Test func everyStudentAtMostOncePerLessonThenPoolIsEmpty() throws {
        let (store, classID) = makeStore(names: ["Adam", "Bára", "Cyril"])
        var generator = SeededGenerator(seed: 3)
        var drawn: [UUID] = []
        for result in [DrawResult.present, .skipped, .absent] {
            guard case .drawn(let student) = store.drawNext(in: classID, using: &generator) else {
                Issue.record("Expected a draw")
                return
            }
            drawn.append(student.id)
            store.recordResult(result, in: classID)
        }
        #expect(Set(drawn).count == 3)
        #expect(store.drawNext(in: classID, using: &generator) == .poolEmpty)
    }

    @Test func cannotDrawWhileTheNameWaitsForAnArrow() {
        let (store, classID) = makeStore(names: ["Adam", "Bára"])
        var generator = SeededGenerator(seed: 5)
        _ = store.drawNext(in: classID, using: &generator)
        #expect(store.drawNext(in: classID, using: &generator) == .needsResult)
        #expect(lastDraws(store, classID).count == 1)
    }

    @Test func undoRevertsDecisionAndItsWeight() throws {
        let (store, classID) = makeStore(names: ["Adam", "Bára"])
        var generator = SeededGenerator(seed: 9)
        guard case .drawn(let student) = store.drawNext(in: classID, using: &generator) else {
            Issue.record("Expected a draw")
            return
        }
        store.recordResult(.present, in: classID)
        #expect(store.schoolClass(classID)?.recordedDrawCount(of: student.id) == 1)

        store.undoLastStep(in: classID)
        #expect(lastDraws(store, classID).map(\.result) == [.pending])
        #expect(store.schoolClass(classID)?.recordedDrawCount(of: student.id) == 0)

        store.recordResult(.absent, in: classID)
        #expect(lastDraws(store, classID).map(\.result) == [.absent])

        // Undo twice: the decision, then the draw itself (the name returns to the pool).
        store.undoLastStep(in: classID)
        store.undoLastStep(in: classID)
        #expect(lastDraws(store, classID).isEmpty)
    }

    @Test func correctionsChangeWeights() throws {
        let (store, classID) = makeStore(names: ["Adam"])
        var generator = SeededGenerator(seed: 11)
        guard case .drawn(let student) = store.drawNext(in: classID, using: &generator) else {
            Issue.record("Expected a draw")
            return
        }
        store.recordResult(.skipped, in: classID)
        let drawID = try #require(lastDraws(store, classID).first?.id)
        store.correctResult(of: drawID, to: .absent, in: classID)
        #expect(store.schoolClass(classID)?.recordedDrawCount(of: student.id) == 1)
        store.correctResult(of: drawID, to: .skipped, in: classID)
        #expect(store.schoolClass(classID)?.recordedDrawCount(of: student.id) == 0)
    }

    @Test func lateJoinerStartsLevelWithTheLeastDrawnStudent() throws {
        let (store, classID) = makeStore(names: ["Adam", "Bára"])
        var generator = SeededGenerator(seed: 13)
        // Draw both and record them: each has n = 1.
        for _ in 0..<2 {
            _ = store.drawNext(in: classID, using: &generator)
            store.recordResult(.present, in: classID)
        }
        store.addStudents(["Cyril"], to: classID)
        let schoolClass = try #require(store.schoolClass(classID))
        let cyril = try #require(schoolClass.students.first { $0.name == "Cyril" })
        #expect(cyril.virtualDrawCount == 1)
        #expect(schoolClass.recordedDrawCount(of: cyril.id) == 0) // nothing real to export

        // In the next lesson all three have the same weight.
        store.createLesson(in: classID)
        let next = try #require(store.schoolClass(classID))
        let weights = DrawEngine.weightedPool(for: next, lesson: next.lastLesson!).map(\.weight)
        #expect(weights == [0.5, 0.5, 0.5])
    }

    @Test func closedLessonsCannotBeDrawnInto() throws {
        let (store, classID) = makeStore(names: ["Adam"])
        store.archiveClass(classID)
        var generator = SeededGenerator(seed: 17)
        #expect(store.drawNext(in: classID, using: &generator) == .notAllowed)
    }
}
