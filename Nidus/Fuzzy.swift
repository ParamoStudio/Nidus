//
//  Fuzzy.swift
//  Nidus
//
//  Lightweight subsequence fuzzy matching for the Greeting Panel project search.
//  "lum" matches "Lumen"; contiguous and prefix matches rank higher.
//

import Foundation

enum Fuzzy {
    /// Returns a score if `query` is a subsequence of `candidate` (diacritic/case-insensitive),
    /// or `nil` if it doesn't match. Higher is better.
    static func score(query: String, candidate: String) -> Int? {
        let q = normalize(query)
        let c = normalize(candidate)
        guard !q.isEmpty else { return nil }
        guard !c.isEmpty else { return nil }

        var score = 0
        var qIndex = q.startIndex
        var previousMatchOffset = -1
        var offset = 0

        for char in c {
            if qIndex < q.endIndex, char == q[qIndex] {
                // Reward contiguous matches and matches at the start.
                if previousMatchOffset == offset - 1 { score += 5 }
                if offset == 0 { score += 10 }
                score += 1
                previousMatchOffset = offset
                qIndex = q.index(after: qIndex)
            }
            offset += 1
        }

        // All query characters consumed → it's a match.
        guard qIndex == q.endIndex else { return nil }
        // Shorter candidates with the same match are slightly preferred.
        score -= c.count / 8
        return score
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
    }
}
