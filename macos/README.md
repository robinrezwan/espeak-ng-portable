# macOS

eSpeak NG has no official macOS release, so the macOS package is built from the upstream source
(`sourceUrl` in `../espeak-ng.json`), without changes.

## How the package is built

`macos/package.sh`:

1. Downloads the upstream source.
2. Builds it with CMake for the machine's architecture, for macOS 11 or later. Audio playback (pcaudiolib)
   and MBROLA are turned off, and Homebrew folders are ignored, so the package needs nothing outside its
   folder. sonic, for fast speech rates, is built into the library from the commit pinned by upstream.
3. Copies the program, `libespeak-ng.dylib` and all language data. It points the program's rpath at
   `@executable_path`, so the program finds the library next to itself, then signs both ad hoc.
4. Checks the program and library only depend on system libraries and each other, and adds the license
   files from the source and a `NOTICE.txt`.
5. Runs a smoke test: `hello world` must come out as `həlˈoʊ wˈɜːld`.
6. Writes `dist/espeak-ng-<version>-macos-<arch>.zip`, where `<arch>` is `arm64` or `x64`.

The `Package` workflow runs it on an Apple silicon runner and an Intel runner.

## Building locally

You need the Xcode Command Line Tools, CMake 3.23 or later, git, and jq:

```
./macos/package.sh
```

It builds for the architecture of the machine it runs on.

The packages are signed ad hoc, not notarized. A zip downloaded with a browser gets the quarantine flag,
and macOS then blocks the program. Remove the flag after unzipping:

```
xattr -dr com.apple.quarantine espeak-ng
```
