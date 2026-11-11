import Foundation

/// Превращает HTML/XHTML главы в чистый текст. Работает на фоновом потоке.
enum HTMLText {
    static func plainText(from html: String) -> String {
        var s = html
        s = replace(s, #"(?is)<(script|style|head|nav|footer|aside)[^>]*>.*?</\1>"#, with: " ")
        s = replace(s, #"(?i)<br\s*/?>"#, with: "\n")
        s = replace(s, #"(?i)</(p|div|h[1-6]|li|blockquote)>"#, with: "\n\n")
        s = replace(s, #"(?s)<[^>]+>"#, with: "")
        s = decodeEntities(s)
        s = replace(s, #"[ \t\u{00A0}]+"#, with: " ")
        s = replace(s, #"\n\s*\n\s*"#, with: "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    static func replace(_ text: String, _ pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func decodeEntities(_ text: String) -> String {
        let map = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                   "&#39;": "'", "&apos;": "'", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
                   "&laquo;": "«", "&raquo;": "»"]
        var s = text
        for (k, v) in map { s = s.replacingOccurrences(of: k, with: v) }
        // Числовые сущности: &#8212; и &#x2014;
        guard let re = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let isHex = ns.substring(with: m.range(at: 1)) == "x"
            let num = UInt32(ns.substring(with: m.range(at: 2)), radix: isHex ? 16 : 10)
            if let num, let scalar = Unicode.Scalar(num) { result.unicodeScalars.append(scalar) }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
