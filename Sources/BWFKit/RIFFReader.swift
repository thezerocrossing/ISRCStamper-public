// Copyright © 2026 Shane Baker and The Zero Crossing LLC
// GPL-2.0-or-later

import Foundation

public enum RIFFReader {

    /// Parse WAV/RF64/BW64 metadata without loading audio data.
    public static func read(_ url: URL) throws -> WaveFile {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw BWFError.ioError("cannot open \(url.lastPathComponent): \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
        } catch {
            throw BWFError.ioError("cannot stat \(url.lastPathComponent)")
        }

        guard fileSize >= 12 else { throw BWFError.notAWaveFile("file too small") }

        let header = try handle.readExactly(12, at: 0, context: "RIFF header")
        let magic = String(decoding: header[0..<4], as: UTF8.self)
        guard let container = WaveContainer(rawValue: magic) else {
            throw BWFError.notAWaveFile("magic is '\(magic)'")
        }
        let form = String(decoding: header[8..<12], as: UTF8.self)
        guard form == "WAVE" else { throw BWFError.notAWaveFile("form type is '\(form)'") }

        // RF64/BW64 stores 64-bit sizes in ds64.
        var ds64DataSize: UInt64? = nil
        var ds64Table: [String: UInt64] = [:]

        var chunks: [RIFFChunk] = []
        var offset: UInt64 = 12

        while offset + 8 <= fileSize {
            let hdr = try handle.readExactly(8, at: offset, context: "chunk header at \(offset)")
            let id = String(decoding: hdr[hdr.startIndex..<hdr.startIndex + 4], as: UTF8.self)
            let size32 = UInt32(littleEndianData: hdr.subdata(in: hdr.startIndex + 4..<hdr.startIndex + 8))
            let dataOffset = offset + 8

            var size = UInt64(size32)

            if container != .wave {
                if id == "ds64" {
                    // ds64: riffSize(8) dataSize(8) sampleCount(8) tableLength(4) [table...]
                    guard size >= 28 else { throw BWFError.truncated("ds64 chunk too small") }
                    let payload = try handle.readExactly(Int(min(size, 4096)), at: dataOffset, context: "ds64")
                    ds64DataSize = UInt64(littleEndianData: payload.subdata(in: 8..<16))
                    let tableCount = UInt32(littleEndianData: payload.subdata(in: 24..<28))
                    var p = 28
                    for _ in 0..<tableCount {
                        guard p + 12 <= payload.count else { break }
                        let tid = String(decoding: payload.subdata(in: p..<p + 4), as: UTF8.self)
                        let tsize = UInt64(littleEndianData: payload.subdata(in: p + 4..<p + 12))
                        ds64Table[tid] = tsize
                        p += 12
                    }
                } else if size32 == 0xFFFF_FFFF {
                    if id == "data", let ds = ds64DataSize {
                        size = ds
                    } else if let ts = ds64Table[id] {
                        size = ts
                    } else {
                        throw BWFError.truncated("chunk '\(id)' has 0xFFFFFFFF size but no ds64 entry")
                    }
                }
            }

            // Tolerate a final chunk whose declared size overruns EOF.
            if dataOffset + size > fileSize {
                size = fileSize - dataOffset
            }

            chunks.append(RIFFChunk(id: id, headerOffset: offset, dataOffset: dataOffset, size: size))
            offset = dataOffset + size + (size & 1)
        }

        var format: WaveFormat? = nil
        if let fmt = chunks.first(where: { $0.id == "fmt " }), fmt.size >= 16 {
            let d = try handle.readExactly(16, at: fmt.dataOffset, context: "fmt chunk")
            format = WaveFormat(
                formatTag: UInt16(littleEndianData: d.subdata(in: 0..<2)),
                channels: UInt16(littleEndianData: d.subdata(in: 2..<4)),
                sampleRate: UInt32(littleEndianData: d.subdata(in: 4..<8)),
                bitsPerSample: UInt16(littleEndianData: d.subdata(in: 14..<16)),
                blockAlign: UInt16(littleEndianData: d.subdata(in: 12..<14))
            )
        }

        let dataSize = chunks.first(where: { $0.id == "data" })?.size ?? 0

        var existingISRC: String? = nil
        if let axml = chunks.first(where: { $0.id == "axml" }) {
            // Cap metadata reads defensively.
            let d = try handle.readExactly(Int(min(axml.size, 1 << 20)), at: axml.dataOffset, context: "axml chunk")
            existingISRC = AXML.extractISRC(from: d)
        }

        return WaveFile(
            url: url,
            container: container,
            fileSize: fileSize,
            chunks: chunks,
            format: format,
            dataSize: dataSize,
            existingISRC: existingISRC,
            hasBext: chunks.contains { $0.id == "bext" }
        )
    }
}
