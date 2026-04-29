import AppKit
import Foundation

enum MarkdownPasteConverter {
    static func bestString(from pasteboard: NSPasteboard) -> String? {
        if let text = pasteboard.string(forType: .string) {
            return text
        }

        if let url = pasteboard.string(forType: .URL), !url.isEmpty {
            return url
        }

        if let htmlData = pasteboard.data(forType: .html),
           let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .utf16) {
            return htmlToMarkdown(html)
        }

        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return attributed.string
        }

        return nil
    }

    static func htmlToMarkdown(_ html: String) -> String {
        var result = html

        result = result.replacingOccurrences(
            of: #"(?is)<a\s+[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#,
            with: #"[$2]($1)"#,
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)</p\s*>"#, with: "\n\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)</div\s*>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)</li\s*>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)<li[^>]*>"#, with: "- ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?is)<style.*?</style>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?is)<script.*?</script>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: "", options: .regularExpression)
        result = decodeEntities(result)

        let lines = result
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return lines
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " "
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
