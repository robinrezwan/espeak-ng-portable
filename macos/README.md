# macOS

Not available yet.

eSpeak NG has no official macOS release, so the macOS package has to be built from the upstream source
(`sourceUrl` in `../espeak-ng.json`), without changes.

When it is added, it should match the Windows package:

- A `macos/package.sh` script that writes `dist/espeak-ng-<version>-macos-<arch>.zip`, where `<arch>` is
  `arm64` or `x64`.
- The zip contains one `espeak-ng/` folder with the `espeak-ng` program, `libespeak-ng.dylib`, all of
  `espeak-ng-data/`, the license files from `licenseFiles`, and a `NOTICE.txt`.
- The program finds `libespeak-ng.dylib` next to itself (for example through an `@executable_path` rpath),
  so the folder works from anywhere.
- The same smoke test as Windows: `hello world` with `-v en-us` gives `həlˈoʊ wˈɜːld`.
- A matching job in `.github/workflows/package.yml`, added to the `release` job's `needs`.
