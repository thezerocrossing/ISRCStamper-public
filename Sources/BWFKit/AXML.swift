// Copyright © 2026 Shane Baker and The Zero Crossing LLC
// GPL-2.0-or-later

import Foundation

/// EBU Tech 3352 axml metadata carrying an ISRC in dc:identifier.
/// Shape verified against a Sequoia-written reference file.
public enum AXML {

    public static func build(isrc: ISRC) -> Data {
        let xml = """
        <ebucore:ebuCoreMain xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:ebucore="urn:ebu:metadata-schema:ebuCore_2012">
        <ebucore:coreMetadata>
        <ebucore:identifier typeLabel="GUID" typeDefinition="Globally Unique Identifier" formatLabel="ISRC" formatDefinition="International Standard Recording Code" formatLink="http://www.ebu.ch/metadata/cs/ebu_IdentifierTypeCodeCS.xml#3.7">
        <dc:identifier>ISRC:\(isrc.code)</dc:identifier>
        </ebucore:identifier>
        </ebucore:coreMetadata>
        </ebucore:ebuCoreMain>
        """
        return Data(xml.utf8)
    }

    private static let isrcPattern = try! NSRegularExpression(
        pattern: #"ISRC[:\s]*([A-Z]{2}[-\s]?[A-Z0-9]{3}[-\s]?[0-9]{2}[-\s]?[0-9]{5})"#
    )

    /// Extract an ISRC from axml metadata, if present.
    public static func extractISRC(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = isrcPattern.firstMatch(in: text, range: range),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return ISRC(String(text[r]))?.code
    }

    /// Replace an existing ISRC while preserving other axml metadata.
    /// Returns nil if no ISRC is present.
    public static func replacingISRC(in data: Data, with isrc: ISRC) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = isrcPattern.firstMatch(in: text, range: range),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        var newText = text
        newText.replaceSubrange(r, with: isrc.code)
        return Data(newText.utf8)
    }
}
