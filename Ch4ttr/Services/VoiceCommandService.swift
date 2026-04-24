import Foundation

final class VoiceCommandService {
    struct CommandResult: Equatable {
        var text: String
        var shouldStopRecording: Bool
        var handledCommand: Bool
    }

    private enum CommandKind {
        case restart
        case restartParagraph
        case start
        case end
    }

    private struct ParsedCommand {
        var kind: CommandKind
        var endIndex: Int
    }

    private enum Token: Equatable {
        case word(String)
        case punctuation(Character)

        var wordValue: String? {
            if case .word(let value) = self { return value }
            return nil
        }

        var isSentenceBoundary: Bool {
            if case .punctuation(let ch) = self {
                return ch == "." || ch == "!" || ch == "?"
            }
            return false
        }

        var isPunctuation: Bool {
            if case .punctuation = self { return true }
            return false
        }
    }

    func apply(to text: String) -> CommandResult {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else {
            return CommandResult(text: "", shouldStopRecording: false, handledCommand: false)
        }

        var output: [Token] = []
        var shouldStopRecording = false
        var handledCommand = false
        var index = 0

        while index < tokens.count {
            if isTrigger(tokens[index]), let command = parseCommand(startingAt: index, in: tokens) {
                handledCommand = true
                var shouldEndLoop = false

                switch command.kind {
                case .restart:
                    output.removeAll()

                case .restartParagraph:
                    trimToPreviousSentenceBoundary(&output)

                case .start:
                    output.removeAll()

                case .end:
                    shouldStopRecording = true
                    shouldEndLoop = true
                }

                index = command.endIndex
                if shouldEndLoop {
                    break
                }
                continue
            }

            output.append(tokens[index])
            index += 1
        }

        return CommandResult(
            text: render(output),
            shouldStopRecording: shouldStopRecording,
            handledCommand: handledCommand
        )
    }

    private func parseCommand(startingAt triggerIndex: Int, in tokens: [Token]) -> ParsedCommand? {
        guard var commandIndex = nextWordIndex(after: triggerIndex, in: tokens) else {
            return nil
        }

        while commandIndex < tokens.count, isTrigger(tokens[commandIndex]) {
            guard let next = nextWordIndex(after: commandIndex, in: tokens) else {
                return nil
            }
            commandIndex = next
        }

        guard let commandWord = normalizedWord(at: commandIndex, in: tokens) else {
            return nil
        }

        switch commandWord {
        case "restart":
            if let paragraphIndex = paragraphCommandIndex(after: commandIndex, in: tokens) {
                return ParsedCommand(
                    kind: .restartParagraph,
                    endIndex: firstIndexAfterCommand(lastWordIndex: paragraphIndex, in: tokens)
                )
            }
            return ParsedCommand(
                kind: .restart,
                endIndex: firstIndexAfterCommand(lastWordIndex: commandIndex, in: tokens)
            )

        case "start":
            return ParsedCommand(
                kind: .start,
                endIndex: firstIndexAfterCommand(lastWordIndex: commandIndex, in: tokens)
            )

        case "end", "stop":
            return ParsedCommand(
                kind: .end,
                endIndex: firstIndexAfterCommand(lastWordIndex: commandIndex, in: tokens)
            )

        default:
            return nil
        }
    }

    private func paragraphCommandIndex(after commandIndex: Int, in tokens: [Token]) -> Int? {
        guard var nextIndex = nextWordIndex(after: commandIndex, in: tokens) else {
            return nil
        }

        while let word = normalizedWord(at: nextIndex, in: tokens),
              word == "the" || word == "this" || word == "current" || word == "my" {
            guard let followingIndex = nextWordIndex(after: nextIndex, in: tokens) else {
                return nil
            }
            nextIndex = followingIndex
        }

        guard normalizedWord(at: nextIndex, in: tokens) == "paragraph" else {
            return nil
        }
        return nextIndex
    }

    private func firstIndexAfterCommand(lastWordIndex: Int, in tokens: [Token]) -> Int {
        var index = lastWordIndex + 1
        while index < tokens.count, tokens[index].isPunctuation {
            index += 1
        }
        return index
    }

    private func trimToPreviousSentenceBoundary(_ tokens: inout [Token]) {
        guard let boundaryIndex = tokens.lastIndex(where: \.isSentenceBoundary) else {
            tokens.removeAll()
            return
        }

        tokens.removeSubrange((boundaryIndex + 1)..<tokens.count)
    }

    private func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var currentWord = ""

        func flushWord() {
            guard !currentWord.isEmpty else { return }
            tokens.append(.word(currentWord))
            currentWord = ""
        }

        for ch in text {
            if ch.isLetter || ch.isNumber || ch == "'" || ch == "’" || ch == "-" {
                currentWord.append(ch)
            } else if ch == "." || ch == "," || ch == "!" || ch == "?" || ch == ";" || ch == ":" {
                flushWord()
                tokens.append(.punctuation(ch))
            } else {
                flushWord()
            }
        }
        flushWord()

        return tokens
    }

    private func render(_ tokens: [Token]) -> String {
        var out = ""

        for token in tokens {
            switch token {
            case .word(let word):
                if !out.isEmpty {
                    out.append(" ")
                }
                out.append(word)

            case .punctuation(let punctuation):
                guard !out.isEmpty else { continue }
                if out.last == " " {
                    out.removeLast()
                }
                out.append(punctuation)
            }
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nextWordIndex(after index: Int, in tokens: [Token]) -> Int? {
        var nextIndex = index + 1
        while nextIndex < tokens.count {
            if tokens[nextIndex].wordValue != nil {
                return nextIndex
            }
            nextIndex += 1
        }
        return nil
    }

    private func isTrigger(_ token: Token) -> Bool {
        normalizedWord(token.wordValue ?? "") == "chatter"
    }

    private func normalizedWord(at index: Int, in tokens: [Token]) -> String? {
        guard let word = tokens[index].wordValue else { return nil }
        return normalizedWord(word)
    }

    private func normalizedWord(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet(charactersIn: "'’-"))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
