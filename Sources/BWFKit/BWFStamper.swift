// Copyright © 2026 Shane Baker and The Zero Crossing LLC
// GPL-2.0-or-later

import Foundation

public struct StampResult {
    public let outputURL: URL
    public let warnings: [String]
}

/// Stamps ISRC metadata into WAV/RF64/BW64 while preserving audio and existing chunks.
/// Audio data is copied verbatim and never decoded.
public enum BWFStamper {

    private static let copyBufferSize = 4 << 20

    public static func stamp(
        sourceURL: URL,
        isrc: ISRC,
        destinationURL: URL,
        originator: String = "ISRC Stamper"
    ) throws -> StampResult {
        let source = try RIFFReader.read(sourceURL)
        var warnings: [String] = []

        guard source.chunk("data") != nil else {
            throw BWFError.notAWaveFile("no data chunk in \(sourceURL.lastPathComponent)")
        }

        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: sourceURL)
        } catch {
            throw BWFError.ioError("cannot open \(sourceURL.lastPathComponent)")
        }
        defer { try? input.close() }

        var axmlData = AXML.build(isrc: isrc)
        if let existing = source.chunk("axml") {
            let old = try input.readExactly(Int(min(existing.size, 1 << 20)),
                                            at: existing.dataOffset, context: "axml")
            if let merged = AXML.replacingISRC(in: old, with: isrc) {
                axmlData = merged
            } else if !old.allSatisfy({ $0 == 0 }) {
                warnings.append("Existing axml chunk had no ISRC; it was replaced.")
            }
        }

        let bextData: Data? = source.hasBext
            ? nil
            : Bext.create(originator: originator, format: source.format)

        let keptChunks = source.chunks.filter { $0.id != "axml" }

        func paddedTotal(_ payload: UInt64) -> UInt64 { 8 + payload + (payload & 1) }
        var projected: UInt64 = 12
        for c in keptChunks { projected += paddedTotal(c.size) }
        if let b = bextData { projected += paddedTotal(UInt64(b.count)) }
        projected += paddedTotal(UInt64(axmlData.count))

        var outputContainer = source.container
        var upgradeToRF64 = false
        if source.container == .wave && projected - 8 > UInt64(UInt32.max) - 1 {
            outputContainer = .rf64
            upgradeToRF64 = true
            projected += paddedTotal(28)
            warnings.append("Output exceeds 4 GiB; file was written as RF64.")
        }

        let destDir = destinationURL.deletingLastPathComponent()
        let tempURL = destDir.appendingPathComponent(
            ".isrcstamper-\(UUID().uuidString.prefix(8))-\(destinationURL.lastPathComponent)")
        guard FileManager.default.createFile(atPath: tempURL.path, contents: nil) else {
            throw BWFError.ioError("cannot create file in \(destDir.path)")
        }
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: tempURL) } }

        let out: FileHandle
        do {
            out = try FileHandle(forWritingTo: tempURL)
        } catch {
            throw BWFError.ioError("cannot open temp file for writing")
        }
        defer { try? out.close() }

        var ds64PayloadOffsetInOutput: UInt64? = nil
        var written: UInt64 = 0

        func write(_ d: Data) throws {
            do { try out.write(contentsOf: d) } catch {
                throw BWFError.ioError("write failed: \(error.localizedDescription)")
            }
            written += UInt64(d.count)
        }

        func writeChunk(id: String, payload: Data) throws {
            try write(Data(id.utf8))
            try write(UInt32(payload.count).littleEndianData)
            try write(payload)
            if payload.count & 1 == 1 { try write(Data([0])) }
        }

        func copyRange(from offset: UInt64, count: UInt64) throws {
            try input.seek(toOffset: offset)
            var remaining = count
            while remaining > 0 {
                let n = Int(min(UInt64(copyBufferSize), remaining))
                guard let buf = try input.read(upToCount: n), !buf.isEmpty else {
                    throw BWFError.truncated("source ended while copying")
                }
                try write(buf)
                remaining -= UInt64(buf.count)
            }
        }

        let magic = outputContainer == .wave ? "RIFF" : (source.container == .bw64 ? "BW64" : "RF64")
        try write(Data(magic.utf8))
        try write(UInt32(outputContainer == .wave ? 0 : 0xFFFF_FFFF).littleEndianData)
        try write(Data("WAVE".utf8))

        if upgradeToRF64 {
            // Synthesized ds64; riffSize is patched after writing.
            let dataChunk = source.chunk("data")!
            var ds64 = Data()
            ds64.append(UInt64(0).littleEndianData)
            ds64.append(dataChunk.size.littleEndianData)
            let frames = source.format.map { $0.blockAlign > 0 ? dataChunk.size / UInt64($0.blockAlign) : 0 } ?? 0
            ds64.append(frames.littleEndianData)
            ds64.append(UInt32(0).littleEndianData)
            ds64PayloadOffsetInOutput = written + 8
            try writeChunk(id: "ds64", payload: ds64)
        }

        // Preserve chunk contents and ordering.
        for chunk in keptChunks {
            if chunk.id == "ds64" && source.container != .wave {
                ds64PayloadOffsetInOutput = written + 8
            }

            if upgradeToRF64 && chunk.id == "data" {
                // RF64 data chunks use 0xFFFFFFFF; the real size is stored in ds64.
                try write(Data("data".utf8))
                try write(UInt32(0xFFFF_FFFF).littleEndianData)
                try copyRange(from: chunk.dataOffset, count: chunk.size)
                if chunk.size & 1 == 1 { try write(Data([0])) }
                continue
            }

            // Preserve the original chunk header, including RF64 size markers.
            try copyRange(from: chunk.headerOffset, count: 8)
            // Supply a missing final pad byte if necessary.
            try copyRange(from: chunk.dataOffset, count: chunk.size)
            if chunk.size & 1 == 1 {
                if chunk.paddedEnd <= source.fileSize {
                    try copyRange(from: chunk.dataOffset + chunk.size, count: 1)
                } else {
                    try write(Data([0]))
                }
            }
        }

        if let bextData {
            try writeChunk(id: "bext", payload: bextData)
        }
        try writeChunk(id: "axml", payload: axmlData)

        let riffSize = written - 8
        if outputContainer == .wave {
            guard riffSize <= UInt64(UInt32.max) else {
                throw BWFError.unsupported("internal error: WAV output overflowed 32-bit size")
            }
            try out.seek(toOffset: 4)
            try out.write(contentsOf: UInt32(riffSize).littleEndianData)
        } else {
            guard let ds64Offset = ds64PayloadOffsetInOutput else {
                throw BWFError.truncated("RF64 source has no ds64 chunk")
            }
            try out.seek(toOffset: ds64Offset)
            try out.write(contentsOf: riffSize.littleEndianData)
        }
        try out.synchronize()
        try out.close()

        let check = try RIFFReader.read(tempURL)
        guard check.existingISRC == isrc.code else {
            throw BWFError.verifyFailed("ISRC read-back mismatch (got \(check.existingISRC ?? "nothing"))")
        }
        guard check.dataSize == source.dataSize else {
            throw BWFError.verifyFailed("data chunk size changed")
        }
        guard check.format == source.format else {
            throw BWFError.verifyFailed("fmt chunk changed")
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            }
            committed = true
        } catch {
            throw BWFError.ioError("cannot move output into place: \(error.localizedDescription)")
        }

        return StampResult(outputURL: destinationURL, warnings: warnings)
    }
}
