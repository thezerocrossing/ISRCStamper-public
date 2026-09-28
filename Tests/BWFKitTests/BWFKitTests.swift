// Copyright © 2026 Shane Baker and The Zero Crossing LLC
// GPL-2.0-or-later

import XCTest
@testable import BWFKit

final class BWFKitTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bwfkit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Fixtures

    func chunk(_ id: String, _ payload: Data) -> Data {
        var d = Data(id.utf8)
        d.append(UInt32(payload.count).littleEndianData)
        d.append(payload)
        if payload.count & 1 == 1 { d.append(0) }
        return d
    }

    func fmtPayload(sampleRate: UInt32 = 44100, channels: UInt16 = 2, bits: UInt16 = 24) -> Data {
        var d = Data()
        d.append(UInt16(1).littleEndianData)
        d.append(channels.littleEndianData)
        d.append(sampleRate.littleEndianData)
        let blockAlign = channels * bits / 8
        d.append((sampleRate * UInt32(blockAlign)).littleEndianData)
        d.append(blockAlign.littleEndianData)
        d.append(bits.littleEndianData)
        return d
    }

    func makeWAV(dataBytes: Int, extraChunks: [Data] = []) throws -> URL {
        let dataPayload = Data((0..<dataBytes).map { UInt8($0 & 0xFF) })
        var body = Data()
        body.append(chunk("fmt ", fmtPayload()))
        body.append(chunk("data", dataPayload))
        for e in extraChunks { body.append(e) }

        var file = Data("RIFF".utf8)
        file.append(UInt32(body.count + 4).littleEndianData)
        file.append(Data("WAVE".utf8))
        file.append(body)

        let url = tempDir.appendingPathComponent("test-\(UUID().uuidString.prefix(6)).wav")
        try file.write(to: url)
        return url
    }

    func makeRF64(dataBytes: Int) throws -> URL {
        let dataPayload = Data(repeating: 0xAB, count: dataBytes)
        var ds64 = Data()
        var body = Data()
        body.append(chunk("fmt ", fmtPayload(sampleRate: 96000)))
        // RF64 data chunks use 0xFFFFFFFF as the size marker.
        body.append(Data("data".utf8))
        body.append(UInt32(0xFFFF_FFFF).littleEndianData)
        body.append(dataPayload)

        let riffSize = UInt64(4 + 8 + 28 + body.count)
        ds64.append(riffSize.littleEndianData)
        ds64.append(UInt64(dataBytes).littleEndianData)
        ds64.append(UInt64(dataBytes / 6).littleEndianData)
        ds64.append(UInt32(0).littleEndianData)

        var file = Data("RF64".utf8)
        file.append(UInt32(0xFFFF_FFFF).littleEndianData)
        file.append(Data("WAVE".utf8))
        file.append(chunk("ds64", ds64))
        file.append(body)

        let url = tempDir.appendingPathComponent("test-\(UUID().uuidString.prefix(6)).wav")
        try file.write(to: url)
        return url
    }

    // MARK: - ISRC

    func testISRCValidation() {
        XCTAssertEqual(ISRC("AUBM02500152")?.code, "AUBM02500152")
        XCTAssertEqual(ISRC("au-bm0-25-00152")?.code, "AUBM02500152")
        XCTAssertEqual(ISRC("ISRC:USRC17607839")?.code, "USRC17607839")
        XCTAssertEqual(ISRC("US-RC1-76-07839")?.formatted, "US-RC1-76-07839")
        XCTAssertNil(ISRC("1UBM02500152"))
        XCTAssertNil(ISRC("AUBM0250015"))
        XCTAssertNil(ISRC("AUBM025001521"))
        XCTAssertNil(ISRC("AUBM0AB00152"))
        XCTAssertNil(ISRC(""))
    }

    func testISRCListParsing() {
        let pasted = """
        ISRC Codes
        AU-BM0-25-00152
        AUBM02500153
        junk line here
        ISRC:AUBM02500154, AUBM02500155
        Track 6\tAUBM02500156
        """
        let list = ISRC.parseList(pasted)
        XCTAssertEqual(list.map(\.code), [
            "AUBM02500152", "AUBM02500153", "AUBM02500154", "AUBM02500155", "AUBM02500156",
        ])
    }

    // MARK: - Reader

    func testReadPlainWAV() throws {
        let url = try makeWAV(dataBytes: 6000)
        let wav = try RIFFReader.read(url)
        XCTAssertEqual(wav.container, .wave)
        XCTAssertEqual(wav.format?.sampleRate, 44100)
        XCTAssertEqual(wav.format?.bitsPerSample, 24)
        XCTAssertEqual(wav.dataSize, 6000)
        XCTAssertNil(wav.existingISRC)
        XCTAssertFalse(wav.hasBext)
        XCTAssertEqual(wav.durationSeconds!, 1000.0 / 44100.0, accuracy: 1e-9)
    }

    func testReadRF64() throws {
        let url = try makeRF64(dataBytes: 4096)
        let wav = try RIFFReader.read(url)
        XCTAssertEqual(wav.container, .rf64)
        XCTAssertEqual(wav.dataSize, 4096)
        XCTAssertEqual(wav.format?.sampleRate, 96000)
    }

    // MARK: - Stamping

    func testStampPlainWAV() throws {
        // Odd payload exercises RIFF padding.
        let src = try makeWAV(dataBytes: 6001)
        let dst = tempDir.appendingPathComponent("out.wav")
        let isrc = ISRC("AUBM02500152")!
        let result = try BWFStamper.stamp(sourceURL: src, isrc: isrc, destinationURL: dst)
        XCTAssertEqual(result.outputURL, dst)

        let out = try RIFFReader.read(dst)
        XCTAssertEqual(out.existingISRC, "AUBM02500152")
        XCTAssertTrue(out.hasBext)
        XCTAssertEqual(out.dataSize, 6001)
        XCTAssertEqual(out.format, try RIFFReader.read(src).format)

        // RIFF size must exactly cover the file.
        let fileSize = try FileManager.default.attributesOfItem(atPath: dst.path)[.size] as! UInt64
        let header = try FileHandle(forReadingFrom: dst).readExactly(8, at: 0, context: "hdr")
        let riffSize = UInt32(littleEndianData: header.subdata(in: 4..<8))
        XCTAssertEqual(UInt64(riffSize) + 8, fileSize)
    }

    func testStampPreservesForeignChunks() throws {
        let junk = chunk("JUNK", Data("hello proprietary chunk".utf8))
        let src = try makeWAV(dataBytes: 512, extraChunks: [junk])
        let dst = tempDir.appendingPathComponent("out.wav")
        _ = try BWFStamper.stamp(sourceURL: src, isrc: ISRC("USRC17607839")!, destinationURL: dst)

        let out = try RIFFReader.read(dst)
        let junkChunk = out.chunk("JUNK")
        XCTAssertNotNil(junkChunk)
        let h = try FileHandle(forReadingFrom: dst)
        let payload = try h.readExactly(Int(junkChunk!.size), at: junkChunk!.dataOffset, context: "junk")
        XCTAssertEqual(payload, Data("hello proprietary chunk".utf8))
    }

    func testStampReplacesExistingISRCInAxml() throws {
        let oldAxml = AXML.build(isrc: ISRC("AUBM02500152")!)
        let src = try makeWAV(dataBytes: 512, extraChunks: [chunk("axml", oldAxml)])
        XCTAssertEqual(try RIFFReader.read(src).existingISRC, "AUBM02500152")

        let dst = tempDir.appendingPathComponent("out.wav")
        _ = try BWFStamper.stamp(sourceURL: src, isrc: ISRC("USRC17607839")!, destinationURL: dst)

        let out = try RIFFReader.read(dst)
        XCTAssertEqual(out.existingISRC, "USRC17607839")
        XCTAssertEqual(out.chunks.filter { $0.id == "axml" }.count, 1)
    }

    func testStampPreservesExistingBext() throws {
        let bext = Bext.create(originator: "SomeoneElse", format: nil)
        let src = try makeWAV(dataBytes: 512, extraChunks: [chunk("bext", bext)])
        let dst = tempDir.appendingPathComponent("out.wav")
        _ = try BWFStamper.stamp(sourceURL: src, isrc: ISRC("USRC17607839")!, destinationURL: dst)

        let out = try RIFFReader.read(dst)
        let outBext = out.chunk("bext")!
        let h = try FileHandle(forReadingFrom: dst)
        let payload = try h.readExactly(Int(outBext.size), at: outBext.dataOffset, context: "bext")
        XCTAssertEqual(payload, bext)
        XCTAssertEqual(out.chunks.filter { $0.id == "bext" }.count, 1)
    }

    func testStampRF64RoundTrip() throws {
        let src = try makeRF64(dataBytes: 4096)
        let dst = tempDir.appendingPathComponent("out.wav")
        _ = try BWFStamper.stamp(sourceURL: src, isrc: ISRC("GBAYE0500001")!, destinationURL: dst)

        let out = try RIFFReader.read(dst)
        XCTAssertEqual(out.container, .rf64)
        XCTAssertEqual(out.existingISRC, "GBAYE0500001")
        XCTAssertEqual(out.dataSize, 4096)

        // ds64 riffSize must exactly cover the file.
        let fileSize = try FileManager.default.attributesOfItem(atPath: dst.path)[.size] as! UInt64
        let ds64 = out.chunk("ds64")!
        let h = try FileHandle(forReadingFrom: dst)
        let riffSize = UInt64(littleEndianData: try h.readExactly(8, at: ds64.dataOffset, context: "ds64"))
        XCTAssertEqual(riffSize + 8, fileSize)
    }

    func testAxmlMatchesSequoiaShape() {
        let xml = String(decoding: AXML.build(isrc: ISRC("AUBM02500152")!), as: UTF8.self)
        XCTAssertTrue(xml.hasPrefix("<ebucore:ebuCoreMain"))
        XCTAssertTrue(xml.contains("urn:ebu:metadata-schema:ebuCore_2012"))
        XCTAssertTrue(xml.contains("formatLabel=\"ISRC\""))
        XCTAssertTrue(xml.contains("http://www.ebu.ch/metadata/cs/ebu_IdentifierTypeCodeCS.xml#3.7"))
        XCTAssertTrue(xml.contains("<dc:identifier>ISRC:AUBM02500152</dc:identifier>"))
        XCTAssertFalse(xml.contains("<?xml")) // Sequoia writes no XML declaration in axml
    }

    func testBextLayout() {
        let d = Bext.create(originator: "ISRC Stamper",
                            date: Date(timeIntervalSince1970: 1_700_000_000),
                            format: WaveFormat(formatTag: 1, channels: 2, sampleRate: 48000,
                                               bitsPerSample: 24, blockAlign: 6))
        XCTAssertGreaterThanOrEqual(d.count, Bext.fixedSize)
        // Version field at offset 346.
        XCTAssertEqual(UInt16(littleEndianData: d.subdata(in: 346..<348)), 2)
        // Date field at offset 320, "YYYY-MM-DD".
        let date = String(decoding: d.subdata(in: 320..<330), as: UTF8.self)
        XCTAssertTrue(date.hasPrefix("20"))
        let history = String(decoding: d.suffix(from: Bext.fixedSize), as: UTF8.self)
        XCTAssertTrue(history.contains("A=PCM,F=48000,W=24,M=stereo"))
        XCTAssertTrue(history.hasSuffix("\r\n"))
    }
}
