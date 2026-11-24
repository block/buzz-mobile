import Foundation

/// The Markdown agents actually write, styled for a small screen: emphasis,
/// code, headings, lists, quotes and links. Links show their text only, since
/// there is nowhere useful to open them on a watch. Anything unrecognised is
/// shown as written.
public func markdown(_ text: String) -> AttributedString {
    // Styling is for reading on a wrist; something this long is shown as it is.
    if text.count > 4000 { return AttributedString(text) }
    var out = AttributedString()
    var fenced = false
    var first = true
    for line in text.components(separatedBy: "\n") {
        let trimmed = String(line.drop { $0 == " " || $0 == "\t" })
        if trimmed.hasPrefix("```") {
            fenced.toggle()
            continue
        }
        if !first { out += AttributedString("\n") }
        first = false
        if fenced {
            out += styled(line, .code)
            continue
        }
        let indent = String(repeating: " ", count: (line.count - trimmed.count) / 2)
        if let heading = trimmed.firstMatch(of: #/^#{1,6}\s+(.*)$/#) {
            out += inline(String(heading.1), [.stronglyEmphasized])
        } else if let bullet = trimmed.firstMatch(of: #/^[-*+]\s+(.*)$/#) {
            out += AttributedString("\(indent)• ") + inline(String(bullet.1), [])
        } else if trimmed.hasPrefix("> ") {
            out += inline(String(trimmed.dropFirst(2)), [.emphasized])
        } else {
            out += AttributedString(indent) + inline(trimmed, [])
        }
    }
    return out
}

// Longest markers first, so ** is not read as two *.
private let marks: [(String, InlinePresentationIntent)] = [
    ("**", .stronglyEmphasized), ("__", .stronglyEmphasized), ("~~", .strikethrough),
    ("*", .emphasized), ("_", .emphasized),
]

private func styled(_ text: String, _ intent: InlinePresentationIntent) -> AttributedString {
    var piece = AttributedString(text)
    if !intent.isEmpty { piece.inlinePresentationIntent = intent }
    return piece
}

private func isWordCharacter(_ character: Character?) -> Bool {
    character.map { $0.isLetter || $0.isNumber } ?? false
}

private func inline(_ source: String, _ intent: InlinePresentationIntent) -> AttributedString {
    let text = Array(source)
    var out = AttributedString()
    var plain = ""
    func flush() {
        if !plain.isEmpty { out += styled(plain, intent) }
        plain = ""
    }
    func find(_ mark: [Character], from start: Int) -> Int? {
        guard start + mark.count <= text.count else { return nil }
        return (start...(text.count - mark.count)).first { Array(text[$0..<($0 + mark.count)]) == mark }
    }
    /// A `[label](target)` link starting at `at`: its label and where it ends.
    func link(at: Int) -> (label: String, end: Int)? {
        guard at < text.count, text[at] == "[",
              let close = find(["]"], from: at + 1), close > at + 1,
              close + 1 < text.count, text[close + 1] == "(",
              let end = find([")"], from: close + 2), end > close + 2,
              !text[(close + 2)..<end].contains(where: \.isWhitespace)
        else { return nil }
        return (String(text[(at + 1)..<close]), end + 1)
    }
    var i = 0
    scan: while i < text.count {
        if text[i] == "`", let end = find(["`"], from: i + 1), end > i + 1 {
            flush()
            out += styled(String(text[(i + 1)..<end]), intent.union(.code))
            i = end + 1
            continue
        }
        // A backslash makes the next mark literal, as in snake\_case.
        if text[i] == "\\", i + 1 < text.count, !isWordCharacter(text[i + 1]), !text[i + 1].isWhitespace {
            plain.append(text[i + 1])
            i += 2
            continue
        }
        // An inline picture is shown as an attachment, not as text.
        if text[i] == "!", let found = link(at: i + 1) {
            i = found.end
            continue
        }
        if let found = link(at: i) {
            flush()
            out += inline(found.label, intent)
            i = found.end
            continue
        }
        for (mark, style) in marks {
            let symbols = Array(mark)
            guard i + symbols.count <= text.count, Array(text[i..<(i + symbols.count)]) == symbols else { continue }
            let start = i + symbols.count
            guard let end = find(symbols, from: start), end > start else { continue }
            // An opening mark hugs its text; `_` inside a word (snake_case) is not emphasis.
            let opens = !text[start].isWhitespace && !text[end - 1].isWhitespace
            let inWord = mark == "_" &&
                (isWordCharacter(i > 0 ? text[i - 1] : nil) || isWordCharacter(end + 1 < text.count ? text[end + 1] : nil))
            if opens, !inWord {
                flush()
                out += inline(String(text[start..<end]), intent.union(style))
                i = end + symbols.count
                continue scan
            }
        }
        plain.append(text[i])
        i += 1
    }
    flush()
    return out
}
