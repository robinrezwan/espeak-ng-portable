# espeak-ng-portable

Portable builds of [eSpeak NG](https://github.com/espeak-ng/espeak-ng) that run from any folder, with no
installation. Each release packages one upstream eSpeak NG version, unmodified, with all languages.

## Downloads

| Platform                    | Release asset                         |
| --------------------------- | ------------------------------------- |
| Windows x64                 | `espeak-ng-<version>-windows-x64.zip` |
| macOS Apple silicon (arm64) | `espeak-ng-<version>-macos-arm64.zip` |
| macOS Intel (x64)           | `espeak-ng-<version>-macos-x64.zip`   |

The macOS packages need macOS 11 or later.

Every release also contains `espeak-ng-<version>-source.tar.gz`, the exact upstream source for that
version, and `SHA256SUMS.txt`.

## Package contents (Windows)

```
espeak-ng/
├── espeak-ng.exe
├── libespeak-ng.dll
├── msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll   Visual C++ runtime
├── espeak-ng-data/                                      all languages
├── COPYING, COPYING.APACHE, COPYING.BSD2, COPYING.UCD
└── NOTICE.txt
```

## Package contents (macOS)

```
espeak-ng/
├── espeak-ng
├── libespeak-ng.dylib
├── espeak-ng-data/                                      all languages
├── COPYING, COPYING.APACHE, COPYING.BSD2, COPYING.UCD
└── NOTICE.txt
```

The macOS packages are built without audio playback. Write audio to a file with `-w <file.wav>`, or to stdout
with `--stdout`. They are signed ad hoc, not notarized, so after unzipping a download from a browser, remove
the quarantine flag: `xattr -dr com.apple.quarantine espeak-ng`.

## Usage

Always pass `--path`, so eSpeak NG uses the bundled data and never looks for an installed copy:

```
espeak-ng.exe --path="C:\path\to\espeak-ng" -q --ipa -v en-us -b 1 -f input.txt
```

```
./espeak-ng --path="/path/to/espeak-ng" -q --ipa -v en-us -b 1 -f input.txt
```

On Windows, pass text through a UTF-8 file (`-b 1 -f <file>`). Text sent on stdin or as a command-line
argument can come out garbled for accented letters and curly quotes.

## How the Windows package is built

`windows/package.ps1`:

1. Downloads the official MSI from the eSpeak NG release and checks its SHA-256 against `espeak-ng.json`.
2. Unpacks it with an administrative install (`msiexec /a`), which installs nothing on the machine.
3. Copies the program, its library and all language data, adds the Visual C++ runtime DLLs from the build
   machine's Visual Studio, and downloads the license files for that exact upstream version.
4. Runs a smoke test: `hello world` must come out as `həlˈoʊ wˈɜːld`.
5. Writes `dist/espeak-ng-<version>-windows-x64.zip`.

To build locally you need Windows, PowerShell 7, and Visual Studio 2022 or its Build Tools with the C++
workload:

```
./windows/package.ps1
```

## How the macOS packages are built

eSpeak NG has no official macOS release, so `macos/package.sh` builds it from the upstream source,
unmodified. See [`macos/README.md`](macos/README.md) for the details and how to build locally.

## Releasing

1. Update `espeak-ng.json` for the new eSpeak NG version: `version`, `sourceUrl`, `licenseBaseUrl`, the
   MSI URL, and its SHA-256 (`Get-FileHash espeak-ng.msi`).
2. Push to `main`. The `Package` workflow builds and tests every package.
3. Push a tag `v<version>`, or `v<version>-<n>` to re-release the same eSpeak NG version with packaging
   fixes. The workflow publishes a GitHub release with every asset.

## Licenses

- The scripts in this repository are under the MIT license ([`LICENSE`](LICENSE)).
- eSpeak NG is under the GNU General Public License v3.0 or later, with some parts under other licenses.
  Every package includes its license files, and every release includes its source code.
- The Visual C++ runtime DLLs are redistributed under Microsoft's Visual Studio license terms.
