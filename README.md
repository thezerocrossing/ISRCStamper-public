# ISRC Stamper

Native macOS application for embedding ISRC codes into WAV/BWF files.

Compliant with EBU Tech 3352 `axml` and EBU Tech 3285 `bext`.

Validated against Sequoia-written reference files and covered by
RIFF/RF64/BW64 round-trip, preservation, sizing, padding, and ISRC tests.

## Build

    make
    make run
    make test

Requires macOS 13+, Xcode 15+, and Swift 5.9+.

## License

GPL-2.0-or-later.

Alternative licensing is available for proprietary integration or redistribution.
