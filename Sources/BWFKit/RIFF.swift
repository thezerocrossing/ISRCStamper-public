// Copyright © 2026 Shane Baker and The Zero Crossing LLC
// GPL-2.0-or-later

import Foundation

public enum BWFError: Error, LocalizedError {
    case notAWaveFile(String)
    case truncated(String)
    case unsupported(String)
    case ioError(String)
    case verifyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAWaveFile(let s): return "Not a WAV/BWF file: \(s)"
        case .truncated(let s): return "File is truncated or corrupt: \(s)"
        case .unsupported(let s): return "Unsupported: \(s)"
        case .ioError(let s): return "I/O error: \(s)"
        case .verifyFailed(let s): return "Verification failed: \(s)"
        }
    }
}

public enum WaveContainer: String {
    case wave = "RIFF"
    case rf64 = "RF64"
    case bw64 = "BW64"
}

/// One top-level RIFF/RF64/BW64 chunk.
/// `size` is the resolved 64-bit payload size, including ds64 resolution.
public struct RIFFChunk: Equatable {
    public let id: String
    public let headerOffset: UInt64
    public let dataOffset: UInt64
    public let size: UInt64

    public var paddedEnd: UInt64 { dataOffset + size + (size & 1) }
}

public struct WaveFormat: Equatable {
    public let formatTag: UInt16
    public let channels: UInt16
    public let sampleRate: UInt32
    public let bitsPerSample: UInt16
    public let blockAlign: UInt16
}

/// Parsed view of a WAV/BWF/RF64 file: chunk map plus the metadata the app displays.
public struct WaveFile {
    public let url: URL
    public let container: WaveContainer
    public let fileSize: UInt64
    public let chunks: [RIFFChunk]
    public let format: WaveFormat?
    public let dataSize: UInt64
    public let existingISRC: String?
    public let hasBext: Bool

    public var durationSeconds: Double? {
        guard let f = format, f.blockAlign > 0, f.sampleRate > 0 else { return nil }
        return Double(dataSize / UInt64(f.blockAlign)) / Double(f.sampleRate)
    }

    public func chunk(_ id: String) -> RIFFChunk? {
        chunks.first { $0.id == id }
    }
}

extension FixedWidthInteger {
    init(littleEndianData data: Data) {
        var v: Self = 0
        withUnsafeMutableBytes(of: &v) { dest in
            data.withUnsafeBytes { src in
                dest.copyBytes(from: src.prefix(MemoryLayout<Self>.size))
            }
        }
        self = Self(littleEndian: v)
    }

    var littleEndianData: Data {
        withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}

extension FileHandle {
    func readExactly(_ count: Int, at offset: UInt64, context: String) throws -> Data {
        do {
            try seek(toOffset: offset)
            guard let d = try read(upToCount: count), d.count == count else {
                throw BWFError.truncated(context)
            }
            return d
        } catch let e as BWFError {
            throw e
        } catch {
            throw BWFError.ioError("\(context): \(error.localizedDescription)")
        }
    }
}
