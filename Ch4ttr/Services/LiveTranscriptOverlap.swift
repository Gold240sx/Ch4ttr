import Foundation

/// When Apple Speech sends a non-prefix “reset” that is really a rewrite of the same utterance, `previous` often ends with the same clause that `next` begins with. Committing all of `previous` plus all of `next` duplicates that clause.
enum LiveTranscriptOverlap {
    private static func normalizedToken(_ w: String) -> String {
        var t = w.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ",.!?;:\"'’”“".contains(last) {
            t.removeLast()
        }
        return t.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func words(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func comparableWord(_ w: String) -> String {
        var t = w.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last {
            switch last {
            case ".", ",", "!", "?", ";", ":", "\"", "'", "”", "“", "’":
                t.removeLast()
            default:
                return normalizedToken(t)
            }
        }
        return normalizedToken(t)
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + substitutionCost
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    private static func wordsRoughlyEqualPair(_ x: String, _ y: String) -> Bool {
        let nx = comparableWord(x)
        let ny = comparableWord(y)
        if nx == ny { return true }
        let maxLen = max(nx.count, ny.count)
        if maxLen == 0 { return true }
        if abs(nx.count - ny.count) > max(3, maxLen / 2) { return false }
        let d = levenshteinDistance(nx, ny)
        return d <= min(5, max(2, maxLen / 2 + 1))
    }

    /// True when aligned words mostly match (streaming rewrites one or two tokens in the overlap).
    private static func suffixPrefixWordArraysRoughlyAlign(_ a: [String], _ b: [String]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        let k = a.count
        var ok = 0
        for i in 0..<k {
            if wordsRoughlyEqualPair(a[i], b[i]) { ok += 1 }
        }
        let ratio = Double(ok) / Double(k)
        if k < 8 { return ratio >= 0.84 }
        return ratio >= 0.80
    }

    /// Largest `k` such that the last `k` words of `previous` equal the first `k` words of `next` (token-normalized).
    static func longestSuffixPrefixOverlapWordCount(previous: String, next: String) -> Int {
        let pw = words(previous)
        let nw = words(next)
        guard !pw.isEmpty, !nw.isEmpty else { return 0 }
        let maxK = min(pw.count, nw.count)
        let minK = 5
        guard maxK >= minK else { return 0 }
        for k in stride(from: maxK, through: minK, by: -1) {
            let ps = Array(pw.suffix(k))
            let np = Array(nw.prefix(k))
            if suffixPrefixWordArraysRoughlyAlign(ps, np) {
                return k
            }
        }
        return 0
    }

    private static func dropLastWords(_ s: String, count: Int) -> String {
        let w = words(s)
        guard count > 0, count <= w.count else { return s }
        return w.dropLast(count).joined(separator: " ")
    }

    private static func dropFirstWords(_ s: String, count: Int) -> String {
        let w = words(s)
        guard count > 0, count <= w.count else { return "" }
        return w.dropFirst(count).joined(separator: " ")
    }

    /// When `next` is not a prefix-refinement of `previous`, split so a rewritten hypothesis does not repeat a shared clause.
    /// - Returns `(head, tail)`: commit `head` to stable, use `tail` as unstable. If overlap is below threshold, `head` is all of `previous` and `tail` is all of `next`.
    static func splitNonRefinementUpdate(previous: String, next: String, minOverlapWords: Int = 5) -> (head: String, tail: String) {
        let prev = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let nxt = next.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = longestSuffixPrefixOverlapWordCount(previous: prev, next: nxt)
        guard k >= minOverlapWords else {
            return (prev, nxt)
        }
        let head = dropLastWords(prev, count: k).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = dropFirstWords(nxt, count: k).trimmingCharacters(in: .whitespacesAndNewlines)
        return (head, tail)
    }
}
