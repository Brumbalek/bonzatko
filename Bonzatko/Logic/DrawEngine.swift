import Foundation

/// Weighted drawing: weight = 0.5 ^ n, where n = recorded draws (+ virtual count for late joiners).
enum DrawEngine {
    static func weight(drawCount: Int) -> Double {
        pow(0.5, Double(drawCount))
    }

    /// Active students not yet drawn in this lesson (whatever the result).
    static func pool(for schoolClass: SchoolClass, lesson: Lesson) -> [Student] {
        let drawn = Set(lesson.draws.map(\.studentID))
        return schoolClass.activeStudents.filter { !drawn.contains($0.id) }
    }

    static func weightedPool(for schoolClass: SchoolClass, lesson: Lesson) -> [(student: Student, weight: Double)] {
        pool(for: schoolClass, lesson: lesson).map { ($0, weight(drawCount: schoolClass.effectiveDrawCount(of: $0))) }
    }

    /// Picks one student with probability proportional to its weight.
    static func pick<R: RandomNumberGenerator>(from candidates: [(student: Student, weight: Double)], using generator: inout R) -> Student? {
        let total = candidates.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return candidates.first?.student }
        var threshold = Double.random(in: 0..<total, using: &generator)
        for candidate in candidates {
            if threshold < candidate.weight { return candidate.student }
            threshold -= candidate.weight
        }
        return candidates.last?.student
    }

    /// Moments (seconds from start) at which the spinning name changes: fast at first, slowing to a stop.
    /// The last moment equals `duration` and shows the winner.
    static func tickTimes(duration: Double, ticksPerSecond: Double = 14) -> [Double] {
        let count = max(Int(duration * ticksPerSecond), 1)
        return (1...count).map { k in
            // Inverse of an ease-out curve (1 - (1 - x)^3): equal steps in progress, growing gaps in time.
            duration * (1 - pow(1 - Double(k) / Double(count), 1.0 / 3.0))
        }
    }

    /// Names shown during the animation; never the same name twice in a row, ends with the winner.
    static func spinSequence<R: RandomNumberGenerator>(pool: [Student], winner: Student, length: Int, using generator: inout R) -> [String] {
        guard length > 1, pool.count > 1 else { return Array(repeating: winner.name, count: max(length, 1)) }
        var names: [String] = []
        var previous = winner.name
        for _ in 0..<(length - 1) {
            var candidate = pool.randomElement(using: &generator)!.name
            while candidate == previous {
                candidate = pool.randomElement(using: &generator)!.name
            }
            names.append(candidate)
            previous = candidate
        }
        if names.last == winner.name, let other = pool.first(where: { $0.name != winner.name }) {
            names[names.count - 1] = other.name
        }
        return names + [winner.name]
    }
}
