import Foundation

final class CleanupService {
    func cleanupText(_ text: String, language: AppLanguage, dictionary: [DictionaryEntry]) -> String {
        cleanupTranscript(text, language: language, dictionary: dictionary, forceTerminalPeriod: true)
    }

    /// Same pipeline as `cleanupText`, but omits the forced trailing period while `isUtteranceFinal` is false so partials stay prefix-compatible and do not read as finished sentences.
    func cleanupStreamingPartial(_ text: String, language: AppLanguage, dictionary: [DictionaryEntry], isUtteranceFinal: Bool) -> String {
        cleanupTranscript(text, language: language, dictionary: dictionary, forceTerminalPeriod: isUtteranceFinal)
    }

    /// Runs spacing, repeat collapse, dictionary, and capitalization on the **joined** live transcript each update (no forced trailing period). Use after merging stable + unstable segments.
    func postProcessJoinedLiveDisplay(_ text: String, language: AppLanguage, dictionary: [DictionaryEntry]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        var result = normalizeSpacing(trimmed)
        result = applySpeechRepeatCollapse(result)
        result = applyDictionary(result, entries: dictionary)
        result = normalizeSpacing(result)
        result = applySpeechRepeatCollapse(result)

        if language != .hebrew {
            result = capitalizeSentences(result)
        }

        return result
    }

    private func cleanupTranscript(_ text: String, language: AppLanguage, dictionary: [DictionaryEntry], forceTerminalPeriod: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        var result = normalizeSpacing(trimmed)
        result = applySpeechRepeatCollapse(result)

        // Local per-user dictionary: phrase replacements (case-insensitive).
        // This is intentionally deterministic and fully offline.
        result = applyDictionary(result, entries: dictionary)
        result = normalizeSpacing(result)
        result = applySpeechRepeatCollapse(result)

        // Capitalization rules are language-dependent; Hebrew has no casing.
        if language != .hebrew {
            result = capitalizeSentences(result)
        }

        if forceTerminalPeriod {
            if let last = result.last, last != "." && last != "!" && last != "?" {
                result.append(".")
            }
        }

        return result
    }

    private enum SpeechToken: Equatable {
        case word(String)
        case punctuation(Character)

        var wordValue: String? {
            if case .word(let value) = self { return value }
            return nil
        }

        var isPunctuation: Bool {
            if case .punctuation = self { return true }
            return false
        }
    }

    private func normalizeSpacing(_ s: String) -> String {
        var out = s
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        out = applyRegex(
            "(?<=[\\p{Ll}\\p{N}])(?=\\p{Lu}\\p{Ll})",
            to: out,
            replacement: " "
        )
        out = applyRegex("\\s+([.,!?;:])", to: out, replacement: "$1")
        out = applyRegex("([.,!?;:])(?=\\p{L})", to: out, replacement: "$1 ")
        out = applyRegex("\\s+", to: out, replacement: " ")

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Short-phrase collapse then long-span collapse (streaming dictation often repeats whole clauses).
    private func applySpeechRepeatCollapse(_ s: String) -> String {
        let pass1 = collapseAdjacentSpeechRepeats(s)
        return collapseRepeatedConsecutiveWordSpans(pass1)
    }

    /// Removes an immediately following duplicate of the same word run (length ≥ `minSpanWords`), using the same word normalization as short-phrase collapse.
    private func collapseRepeatedConsecutiveWordSpans(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ").map(String.init)
        let minSpanWords = 6
        let maxSpanWords = 100
        guard words.count >= minSpanWords * 2 else { return s }

        var w = words
        var safety = 0
        while safety < 80 {
            safety += 1
            var removed = false
            outer: for i in 0..<w.count {
                let upperSpan = min(maxSpanWords, (w.count - i) / 2)
                if upperSpan < minSpanWords { break }
                for span in stride(from: upperSpan, through: minSpanWords, by: -1) {
                    guard i + 2 * span <= w.count else { continue }
                    let a = w[i..<(i + span)]
                    let b = w[(i + span)..<(i + 2 * span)]
                    if wordSpansMatchForLongRunDeduplication(a, b, span: span) {
                        w.removeSubrange((i + span)..<(i + 2 * span))
                        removed = true
                        break outer
                    }
                }
            }
            if !removed { break }
        }

        return normalizeSpacing(w.joined(separator: " "))
    }

    private func wordSpansMatchForLongRunDeduplication(_ a: ArraySlice<String>, _ b: ArraySlice<String>, span: Int) -> Bool {
        guard a.count == b.count, a.count == span, !a.isEmpty else { return false }
        var mismatchPairs: [(String, String)] = []
        for (x, y) in zip(a, b) {
            let nx = comparableWordForRepeatCollapse(x)
            let ny = comparableWordForRepeatCollapse(y)
            if nx != ny {
                mismatchPairs.append((nx, ny))
            }
        }
        if mismatchPairs.isEmpty { return true }
        guard span >= 10, mismatchPairs.count == 1 else { return false }
        let (nl, nr) = mismatchPairs[0]
        if nl.isEmpty, nr.isEmpty { return true }
        let maxLen = max(nl.count, nr.count)
        let distance = levenshteinDistance(nl, nr)
        return distance <= min(4, max(2, maxLen / 3))
    }

    private func comparableWordForRepeatCollapse(_ w: String) -> String {
        var t = w
        while let last = t.last {
            switch last {
            case ".", ",", "!", "?", ";", ":", "\"", "'", "”", "“", "’":
                t.removeLast()
            default:
                return normalizedWord(t)
            }
        }
        return normalizedWord(t)
    }

    private func collapseAdjacentSpeechRepeats(_ s: String) -> String {
        var tokens = tokenize(s)
        guard tokens.contains(where: { $0.wordValue != nil }) else { return s }

        var didChange = true
        var passCount = 0
        while didChange, passCount < 8 {
            passCount += 1
            didChange = false
            var index = 0

            while index < tokens.count {
                guard tokens[index].wordValue != nil else {
                    index += 1
                    continue
                }

                let maxPhraseLength = min(6, remainingWordCount(from: index, in: tokens) / 2)
                guard maxPhraseLength > 0 else { break }

                var collapsed = false
                for phraseLength in stride(from: maxPhraseLength, through: 1, by: -1) {
                    guard
                        let firstRun = wordIndices(startingAt: index, count: phraseLength, in: tokens),
                        let secondStart = nextWordIndex(after: firstRun[firstRun.count - 1], in: tokens),
                        let secondRun = wordIndices(startingAt: secondStart, count: phraseLength, in: tokens),
                        normalizedWords(at: firstRun, in: tokens) == normalizedWords(at: secondRun, in: tokens)
                    else {
                        continue
                    }

                    var removeStart = firstRun[firstRun.count - 1] + 1
                    var removeEnd = secondRun[secondRun.count - 1]
                    while removeEnd + 1 < tokens.count, tokens[removeEnd + 1].isPunctuation {
                        removeEnd += 1
                    }

                    guard removeStart <= removeEnd else { continue }
                    tokens.removeSubrange(removeStart...removeEnd)
                    didChange = true
                    collapsed = true
                    break
                }

                if !collapsed {
                    index += 1
                }
            }
        }

        return render(tokens)
    }

    private func tokenize(_ s: String) -> [SpeechToken] {
        var tokens: [SpeechToken] = []
        var currentWord = ""

        func flushWord() {
            guard !currentWord.isEmpty else { return }
            tokens.append(.word(currentWord))
            currentWord = ""
        }

        for ch in s {
            if ch.isLetter || ch.isNumber || ch == "'" || ch == "’" || ch == "-" {
                currentWord.append(ch)
            } else if ch == "." || ch == "," || ch == "!" || ch == "?" || ch == ";" || ch == ":" {
                flushWord()
                tokens.append(.punctuation(ch))
            } else if ch.isWhitespace {
                flushWord()
            } else {
                flushWord()
            }
        }
        flushWord()

        return tokens
    }

    private func render(_ tokens: [SpeechToken]) -> String {
        var out = ""
        var previousWasWord = false

        for token in tokens {
            switch token {
            case .word(let word):
                if !out.isEmpty {
                    out.append(" ")
                }
                out.append(word)
                previousWasWord = true

            case .punctuation(let punctuation):
                if !out.isEmpty, out.last == " " {
                    out.removeLast()
                }
                if !out.isEmpty || previousWasWord {
                    out.append(punctuation)
                }
                previousWasWord = false
            }
        }

        return normalizeSpacing(out)
    }

    private func remainingWordCount(from index: Int, in tokens: [SpeechToken]) -> Int {
        tokens[index...].reduce(0) { count, token in
            token.wordValue == nil ? count : count + 1
        }
    }

    private func wordIndices(startingAt start: Int, count: Int, in tokens: [SpeechToken]) -> [Int]? {
        guard count > 0 else { return [] }

        var indices: [Int] = []
        var index = start
        while index < tokens.count, indices.count < count {
            if tokens[index].wordValue != nil {
                indices.append(index)
            }
            index += 1
        }

        return indices.count == count ? indices : nil
    }

    private func nextWordIndex(after index: Int, in tokens: [SpeechToken]) -> Int? {
        var nextIndex = index + 1
        while nextIndex < tokens.count {
            if tokens[nextIndex].wordValue != nil {
                return nextIndex
            }
            nextIndex += 1
        }
        return nil
    }

    private func normalizedWords(at indices: [Int], in tokens: [SpeechToken]) -> [String] {
        indices.compactMap { index in
            guard let word = tokens[index].wordValue else { return nil }
            return normalizedWord(word)
        }
    }

    private func normalizedWord(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet(charactersIn: "'’-"))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func capitalizeSentences(_ s: String) -> String {
        var out = ""
        var capitalizeNext = true
        for ch in s {
            if capitalizeNext, ch.isLetter {
                out.append(String(ch).uppercased())
                capitalizeNext = false
            } else {
                out.append(ch)
                if ch == "." || ch == "!" || ch == "?" {
                    capitalizeNext = true
                }
            }
        }
        return out
    }

    private func applyDictionary(_ s: String, entries: [DictionaryEntry]) -> String {
        var out = s
        let enabledEntries = entries.filter(\.isEnabled)

        for e in enabledEntries {
            let phrase = e.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if phrase.isEmpty { continue }

            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            // Replace with word-ish boundaries where possible, but still allow multi-word phrases.
            let pattern = "(?i)(?<!\\p{L})\(escaped)(?!\\p{L})"
            if let re = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = re.stringByReplacingMatches(in: out, range: range, withTemplate: e.replacement)
            }
        }

        return applyFuzzyDictionary(out, entries: enabledEntries)
    }

    private struct FuzzyDictionaryCandidate {
        let phrase: String
        let replacement: String
        let strength: Double
    }

    private func applyFuzzyDictionary(_ s: String, entries: [DictionaryEntry]) -> String {
        let candidates = entries.compactMap(fuzzyCandidate)
        guard !candidates.isEmpty else { return s }

        var tokens = tokenize(s)
        for index in tokens.indices {
            guard case .word(let word) = tokens[index] else { continue }
            let normalizedInput = normalizedWord(word)
            guard normalizedInput.count >= 4 else { continue }

            var best: (candidate: FuzzyDictionaryCandidate, score: Double)?
            for candidate in candidates {
                guard isFuzzyComparable(normalizedInput, candidate.phrase) else { continue }

                let similarity = stringSimilarity(normalizedInput, candidate.phrase)
                let threshold = 0.90 - (0.34 * candidate.strength)
                guard similarity >= threshold else { continue }

                let score = similarity + (candidate.strength * 0.08)
                if best == nil || score > best!.score {
                    best = (candidate, score)
                }
            }

            if let best {
                tokens[index] = .word(best.candidate.replacement)
            }
        }

        return render(tokens)
    }

    private func fuzzyCandidate(for entry: DictionaryEntry) -> FuzzyDictionaryCandidate? {
        let phrase = entry.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, !replacement.isEmpty else { return nil }

        let words = tokenize(phrase).compactMap(\.wordValue)
        guard words.count == 1 else { return nil }

        let normalizedPhrase = normalizedWord(words[0])
        let normalizedReplacement = normalizedWord(replacement)
        guard normalizedPhrase.count >= 4, normalizedPhrase != normalizedReplacement else { return nil }

        return FuzzyDictionaryCandidate(
            phrase: normalizedPhrase,
            replacement: replacement,
            strength: min(max(entry.replacementStrength, 0), 1)
        )
    }

    private func isFuzzyComparable(_ lhs: String, _ rhs: String) -> Bool {
        let lhsCount = lhs.count
        let rhsCount = rhs.count
        guard lhsCount >= 4, rhsCount >= 4 else { return false }
        guard abs(lhsCount - rhsCount) <= max(2, max(lhsCount, rhsCount) / 2) else {
            return false
        }

        return commonPrefixLength(lhs, rhs) >= min(3, min(lhsCount, rhsCount))
    }

    private func stringSimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else { return 1 }
        let distance = levenshteinDistance(lhs, rhs)
        return 1 - (Double(distance) / Double(maxLength))
    }

    private func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        var lhsIndex = lhs.startIndex
        var rhsIndex = rhs.startIndex

        while lhsIndex < lhs.endIndex, rhsIndex < rhs.endIndex, lhs[lhsIndex] == rhs[rhsIndex] {
            count += 1
            lhsIndex = lhs.index(after: lhsIndex)
            rhsIndex = rhs.index(after: rhsIndex)
        }

        return count
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
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

    private func applyRegex(_ pattern: String, to s: String, replacement: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: replacement)
    }
}
