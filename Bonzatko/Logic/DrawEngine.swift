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
    /// Gaps grow geometrically but never beyond `maxGap`, so the second-to-last name does not linger.
    /// The last moment equals `duration` and shows the winner.
    static func tickTimes(duration: Double, firstGap: Double = 0.04, maxGap: Double = 0.2) -> [Double] {
        guard duration > 0 else { return [0] }
        let last = min(maxGap, duration * 0.15)
        let first = min(firstGap, last / 2)

        // Pick the number of gaps whose geometric series (first … last) best fills the duration.
        func gaps(_ count: Int) -> [Double] {
            guard count > 1 else { return [first] }
            let ratio = pow(last / first, 1 / Double(count - 1))
            return (0..<count).map { first * pow(ratio, Double($0)) }
        }
        let count = (1...400).min { abs(gaps($0).reduce(0, +) - duration) < abs(gaps($1).reduce(0, +) - duration) } ?? 1
        let chosen = gaps(count)
        let scale = duration / chosen.reduce(0, +)

        var time = 0.0
        return chosen.map { gap in
            time += gap * scale
            return time
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
