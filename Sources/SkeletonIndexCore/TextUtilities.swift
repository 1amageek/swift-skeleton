import Foundation

public enum TextUtilities {

    public static func braceBalance(_ line: String) -> Int {
        var balance = 0
        var inString = false
        var prevBackslash = false

        for scalar in line.unicodeScalars {
            if inString {
                if scalar == "\\" {
                    prevBackslash = !prevBackslash
                    continue
                }
                if scalar == "\"" && !prevBackslash {
                    inString = false
                }
                prevBackslash = false
                continue
            }
            if scalar == "\"" {
                inString = true
                prevBackslash = false
            } else if scalar == "{" {
                balance += 1
            } else if scalar == "}" {
                balance -= 1
            }
        }
        return balance
    }

    public static func betweenParentheses(_ text: String) -> String? {
        guard let open = text.firstIndex(of: "(") else {
            return nil
        }

        var depth = 0
        var close: String.Index?

        for index in text.indices where index >= open {
            let char = text[index]
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    close = index
                    break
                }
            }
        }
        guard let close else {
            return nil
        }
        return String(text[text.index(after: open)..<close])
    }

    public static func splitTopLevel(_ text: String, by delimiter: Character) -> [String] {
        var results: [String] = []
        var current = ""
        var parenDepth = 0
        var squareDepth = 0
        var angleDepth = 0
        var braceDepth = 0

        for character in text {
            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                squareDepth += 1
            case "]":
                squareDepth = max(0, squareDepth - 1)
            case "<":
                angleDepth += 1
            case ">":
                angleDepth = max(0, angleDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            if character == delimiter && parenDepth == 0 && squareDepth == 0 && angleDepth == 0 && braceDepth == 0 {
                results.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        results.append(current)
        return results
    }

    public static func firstTopLevelIndex(in text: String, character: Character) -> String.Index? {
        var parenDepth = 0
        var squareDepth = 0
        var angleDepth = 0
        var braceDepth = 0

        for index in text.indices {
            let value = text[index]
            switch value {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                squareDepth += 1
            case "]":
                squareDepth = max(0, squareDepth - 1)
            case "<":
                angleDepth += 1
            case ">":
                angleDepth = max(0, angleDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            if value == character && parenDepth == 0 && squareDepth == 0 && angleDepth == 0 && braceDepth == 0 {
                return index
            }
        }
        return nil
    }

    public static func collectFullSignature(lines: [String], startIndex: Int) -> String {
        var result = lines[startIndex]
        var parenDepth = 0
        for character in result {
            if character == "(" { parenDepth += 1 }
            else if character == ")" { parenDepth -= 1 }
        }
        if parenDepth <= 0 {
            return result
        }
        for index in (startIndex + 1)..<lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            result += " " + line
            for character in line {
                if character == "(" { parenDepth += 1 }
                else if character == ")" { parenDepth -= 1 }
            }
            if parenDepth <= 0 {
                break
            }
        }
        return result
    }

    public static func blockEndLine(lines: [String], startIndex: Int) -> Int? {
        let firstLine = lines[startIndex]
        if !firstLine.contains("{") {
            return startIndex
        }

        var balance = 0
        for index in startIndex..<lines.count {
            balance += braceBalance(lines[index])
            if balance == 0 && index >= startIndex {
                return index
            }
        }
        return nil
    }

    public static func parseParameterTypeRefs(_ parameterSection: String) -> [String] {
        if parameterSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }

        let chunks = splitTopLevel(parameterSection, by: ",")
        return chunks.map { chunk in
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "?"
            }
            guard let colon = firstTopLevelIndex(in: trimmed, character: ":") else {
                return "?"
            }
            let typeStart = trimmed.index(after: colon)
            var typeRef = String(trimmed[typeStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let equalIndex = firstTopLevelIndex(in: typeRef, character: "=") {
                typeRef = String(typeRef[..<equalIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return typeRef.isEmpty ? "?" : typeRef
        }
    }

    public static func firstRegex(pattern: String, in text: String) -> String? {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            return nil
        }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange), match.numberOfRanges >= 2 else {
            return nil
        }
        guard let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return text[captureRange].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    public static func firstRegexCapture(pattern: String, in text: String) -> (String, String)? {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            return nil
        }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange), match.numberOfRanges >= 3 else {
            return nil
        }
        guard
            let leftRange = Range(match.range(at: 1), in: text),
            let rightRange = Range(match.range(at: 2), in: text)
        else {
            return nil
        }
        return (
            text[leftRange].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            text[rightRange].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        )
    }
}
