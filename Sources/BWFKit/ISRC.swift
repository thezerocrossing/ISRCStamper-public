// Copyright © 2026 Shane Baker and The Zero Crossing LLC
// GPL-2.0-or-later

import Foundation

/// International Standard Recording Code.
/// Canonical form: CCXXXYYNNNNN.
public struct ISRC: Equatable, Hashable, CustomStringConvertible {
    public let code: String

    public init?(_ raw: String) {
        var cleaned = raw.uppercased()
        if cleaned.hasPrefix("ISRC:") { cleaned.removeFirst(5) }
        cleaned = cleaned.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard ISRC.isValidCanonical(cleaned) else { return nil }
        self.code = cleaned
    }

    public static func isValidCanonical(_ s: String) -> Bool {
        let chars = Array(s.utf8)
        guard chars.count == 12 else { return false }
        func isUpper(_ c: UInt8) -> Bool { c >= 65 && c <= 90 }
        func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }
        for i in 0..<2 where !isUpper(chars[i]) { return false }
        for i in 2..<5 where !(isUpper(chars[i]) || isDigit(chars[i])) { return false }
        for i in 5..<12 where !isDigit(chars[i]) { return false }
        return true
    }

    /// Display form: CC-XXX-YY-NNNNN.
    public var formatted: String {
        let c = code
        let i = c.startIndex
        return "\(c[i..<c.index(i, offsetBy: 2)])-\(c[c.index(i, offsetBy: 2)..<c.index(i, offsetBy: 5)])-\(c[c.index(i, offsetBy: 5)..<c.index(i, offsetBy: 7)])-\(c[c.index(i, offsetBy: 7)...])"
    }

    public var description: String { code }

    /// Extract ISRCs from pasted text in order.
    public static func parseList(_ text: String) -> [ISRC] {
        var results: [ISRC] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let cells = line.components(separatedBy: CharacterSet(charactersIn: ",;\t"))
            var foundInLine = false
            for cell in cells {
                if let isrc = ISRC(cell) {
                    results.append(isrc)
                    foundInLine = true
                }
            }
            if foundInLine { continue }
            for token in line.split(whereSeparator: { $0.isWhitespace }) {
                if let isrc = ISRC(String(token)) {
                    results.append(isrc)
                }
            }
        }
        return results
    }
}
