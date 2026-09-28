// Copyright © 2026 Shane Baker and The Zero Crossing LLC
// GPL-2.0-or-later

import Foundation
import BWFKit

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("bwfctl: \(msg)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fail("usage: bwfctl read <file.wav> | bwfctl stamp <ISRC> <in.wav> <out.wav>")
}

do {
    switch args[1] {
    case "read":
        let wav = try RIFFReader.read(URL(fileURLWithPath: args[2]))
        print("container: \(wav.container.rawValue)")
        if let f = wav.format {
            print("format:    \(f.sampleRate) Hz, \(f.bitsPerSample)-bit, \(f.channels)ch (tag \(f.formatTag))")
        }
        if let d = wav.durationSeconds {
            print("duration:  \(String(format: "%.3f", d)) s")
        }
        print("bext:      \(wav.hasBext ? "present" : "none")")
        print("ISRC:      \(wav.existingISRC ?? "none")")
        print("chunks:")
        for c in wav.chunks {
            print(String(format: "  %-4@ offset %10llu  size %10llu", c.id as NSString, c.headerOffset, c.size))
        }
    case "stamp":
        guard args.count == 5 else { fail("usage: bwfctl stamp <ISRC> <in.wav> <out.wav>") }
        guard let isrc = ISRC(args[2]) else { fail("'\(args[2])' is not a valid ISRC") }
        let result = try BWFStamper.stamp(
            sourceURL: URL(fileURLWithPath: args[3]),
            isrc: isrc,
            destinationURL: URL(fileURLWithPath: args[4])
        )
        for w in result.warnings { print("warning: \(w)") }
        print("wrote \(result.outputURL.path) with ISRC \(isrc.formatted) (verified)")
    default:
        fail("unknown command '\(args[1])'")
    }
} catch {
    fail(error.localizedDescription)
}
