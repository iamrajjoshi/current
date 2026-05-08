import AppKit

struct MarkdownTypingMarks: Equatable {
    private(set) var marks: Set<MarkdownInlineMark> = []

    var isEmpty: Bool {
        marks.isEmpty
    }

    mutating func toggle(_ kind: MarkdownInlineFormatting.Kind) {
        let mark = MarkdownInlineMark(kind)
        if marks.contains(mark) {
            marks.remove(mark)
            return
        }

        if mark == .inlineCode {
            marks = [.inlineCode]
        } else if !marks.contains(.inlineCode) {
            marks.insert(mark)
        }
    }

    func isSatisfied(by activeMarks: Set<MarkdownInlineMark>) -> Bool {
        marks.isSubset(of: activeMarks)
    }

    func wrap(_ text: String) -> (replacement: String, visibleOffset: Int) {
        let orderedMarks = canonicalMarks()
        let opening = orderedMarks.map(Self.markers(for:)).map(\.open).joined()
        let closing = orderedMarks.reversed().map(Self.markers(for:)).map(\.close).joined()
        return (opening + text + closing, opening.utf16.count + (text as NSString).length)
    }

    func applying(to attributes: [NSAttributedString.Key: Any], configuration: CurrentConfiguration) -> [NSAttributedString.Key: Any] {
        var attributes = attributes
        for mark in canonicalMarks() {
            switch mark {
            case .bold:
                let font = attributes[.font] as? NSFont ?? CurrentTheme.editorFont(configuration: configuration)
                attributes[.font] = CurrentTheme.editorBoldFont(matching: font)
            case .italic:
                attributes[.obliqueness] = 0.12
            case .underline:
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.underlineColor] = CurrentTheme.primaryTextColor
            case .strikethrough:
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case .inlineCode:
                attributes[.font] = CurrentTheme.editorFont(configuration: configuration)
                attributes[.foregroundColor] = CurrentTheme.secondaryTextColor
                attributes[.backgroundColor] = CurrentTheme.inlineCodeBackgroundColor
            }
        }
        return attributes
    }

    private func canonicalMarks() -> [MarkdownInlineMark] {
        if marks.contains(.inlineCode) {
            return [.inlineCode]
        }
        return [.bold, .italic, .underline, .strikethrough].filter { marks.contains($0) }
    }

    private static func markers(for mark: MarkdownInlineMark) -> (open: String, close: String) {
        switch mark {
        case .bold:
            return ("**", "**")
        case .italic:
            return ("_", "_")
        case .underline:
            return ("<u>", "</u>")
        case .strikethrough:
            return ("~~", "~~")
        case .inlineCode:
            return ("`", "`")
        }
    }
}

private extension MarkdownInlineMark {
    init(_ kind: MarkdownInlineFormatting.Kind) {
        switch kind {
        case .bold:
            self = .bold
        case .italic:
            self = .italic
        case .underline:
            self = .underline
        case .strikethrough:
            self = .strikethrough
        case .inlineCode:
            self = .inlineCode
        }
    }
}
