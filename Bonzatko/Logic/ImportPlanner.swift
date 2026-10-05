import Foundation

/// What to do with a name that already exists in the class (or earlier in the same import).
enum DuplicateChoice: String, CaseIterable, Hashable, Sendable {
    case skip
    case addDisambiguated
}

struct ImportCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var duplicateChoice: DuplicateChoice

    init(id: UUID = UUID(), name: String, duplicateChoice: DuplicateChoice = .skip) {
        self.id = id
        self.name = name
        self.duplicateChoice = duplicateChoice
    }
}

struct ImportPlanRow: Hashable, Sendable {
    enum Conflict: Hashable, Sendable {
        case none
        /// Same name as an active student.
        case existingStudent
        /// Same name as a removed student (who can be restored instead).
        case removedStudent
        /// Same name appears earlier in this import.
        case earlierInImport
    }

    let candidateID: UUID
    let conflict: Conflict
    /// Name that will be saved, or `nil` when the row is skipped or empty.
    let finalName: String?
    /// Name proposed if the user chooses to add a duplicate.
    let disambiguatedName: String?
}

/// Decides, row by row, which names get imported and under which name.
enum ImportPlanner {
    static func plan(candidates: [ImportCandidate], existing: [Student]) -> [ImportPlanRow] {
        let activeKeys = Set(existing.filter(\.isActive).map { Names.key($0.name) })
        let removedKeys = Set(existing.filter { !$0.isActive }.map { Names.key($0.name) })
        var taken = activeKeys.union(removedKeys)
        var seenInImport = Set<String>()

        return candidates.map { candidate in
            let name = Names.clean(candidate.name)
            guard !name.isEmpty else {
                return ImportPlanRow(candidateID: candidate.id, conflict: .none, finalName: nil, disambiguatedName: nil)
            }
            let key = Names.key(name)
            let conflict: ImportPlanRow.Conflict
            if activeKeys.contains(key) {
                conflict = .existingStudent
            } else if removedKeys.contains(key) {
                conflict = .removedStudent
            } else if seenInImport.contains(key) {
                conflict = .earlierInImport
            } else {
                conflict = .none
            }
            seenInImport.insert(key)

            guard conflict != .none else {
                taken.insert(key)
                return ImportPlanRow(candidateID: candidate.id, conflict: .none, finalName: name, disambiguatedName: nil)
            }
            let alternative = Names.disambiguate(name, takenKeys: taken)
            if candidate.duplicateChoice == .addDisambiguated {
                taken.insert(Names.key(alternative))
                return ImportPlanRow(candidateID: candidate.id, conflict: conflict, finalName: alternative, disambiguatedName: alternative)
            }
            return ImportPlanRow(candidateID: candidate.id, conflict: conflict, finalName: nil, disambiguatedName: alternative)
        }
    }
}
