# SoX macOS Universal Binary Builder

[Sound eXchange (SoX)](https://en.wikipedia.org/wiki/SoX) is command line audio processing tool. This script builds a self-contained SoX binary for macOS that works on both Intel (x86_64) and Apple Silicon (arm64) processors. The binary includes all necessary libraries statically linked, making it portable and easy to distribute.

## What it builds

The script produces universal binaries for:
- `sox` - The main SoX program
- `soxi` - Display sound file information
- `play` - Play audio files
- `rec` - Record audio files

## Versions

The script automatically downloads and builds:
- SoX 14.4.2
- libsndfile 1.2.2

## How to use

You can download the binaries from the latest GitHub Actions run, in the artefacts tab.

Alternatively, you can build them yourself:

1. Clone this repository
2. Run the build script: `./build.sh` (takes a few minutes)
3. Find the universal binaries in `sox-build/universal/bin/`.
