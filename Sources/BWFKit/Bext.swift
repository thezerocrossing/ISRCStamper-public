// Copyright © 2026 Shane Baker and The Zero Crossing LLC
// GPL-2.0-or-later

import Foundation

/// Builds a minimal EBU Tech 3285 bext chunk.
/// Fixed header is 602 bytes; version 2 uses zeroed UMID and loudness fields.
public enum Bext {
    public static let fixedSize = 602

    public static func create(
        description: String = "",
        originator: String,
        originatorReference: String = "",
        date: Date = Date(),
        timeReference: UInt64 = 0,
        format: WaveFormat?
    ) -> Data {
        var d = Data(capacity: 700)
        d.append(fixedString(description, 256))
        d.append(fixedString(originator, 32))
        d.append(fixedString(originatorReference, 32))

        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let dateStr = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        let timeStr = String(format: "%02d:%02d:%02d", c.hour!, c.minute!, c.second!)
        d.append(fixedString(dateStr, 10))
        d.append(fixedString(timeStr, 8))

        d.append(timeReference.littleEndianData)
        d.append(UInt16(2).littleEndianData)
        d.append(Data(count: 64))
        d.append(Data(count: 10))
        d.append(Data(count: 180))

        var history = "T=\(originator)\r\n"
        if let f = format {
            let mode: String
            switch f.channels {
            case 1: mode = "mono"
            case 2: mode = "stereo"
            default: mode = "\(f.channels)ch"
            }
            history = "A=PCM,F=\(f.sampleRate),W=\(f.bitsPerSample),M=\(mode),T=\(originator)\r\n"
        }
        d.append(Data(history.utf8))
        return d
    }

    private static func fixedString(_ s: String, _ length: Int) -> Data {
        var bytes = Data(s.utf8.prefix(length))
        bytes.append(Data(count: length - bytes.count))
        return bytes
    }
}
