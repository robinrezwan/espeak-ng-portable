#!/usr/bin/env bash

# Build a portable macOS package of eSpeak NG from the upstream source.
#
# Downloads the upstream source, builds it unmodified for Apple silicon, makes the program find its
# library next to itself, and zips the program, its library, all of its language data, and its license
# files into dist/espeak-ng-<version>-macos-arm64.zip.
#
# Needs a Mac with Apple silicon, the Xcode Command Line Tools, CMake 3.23 or later, git, and jq.
#
# Usage: macos/package.sh [output-dir] [work-dir]

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-$repo_root/dist}"
work_dir="${2:-$repo_root/work/macos}"

# The oldest macOS version the package runs on.
deployment_target='11.0'

# Stop unless this is a Mac with Apple silicon, the only architecture the package is built for.
check_arch() {
    if [[ "$(uname -m)" != 'arm64' ]]; then
        echo "Unsupported architecture: $(uname -m). The package is built on Apple silicon (arm64) only." >&2
        exit 1
    fi
}

# Configure, build and install eSpeak NG from a source folder into an install folder.
#
# Audio playback (pcaudiolib) and MBROLA are off, so the package needs nothing outside its folder.
# Homebrew folders are ignored, so a library installed there can't leak into the build. sonic, for fast
# speech rates, is built into the library from the commit pinned by upstream.
build_espeak() {
    local source_dir="$1" build_dir="$2" install_dir="$3"

    rm -rf "$build_dir" "$install_dir"

    cmake -S "$source_dir" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
        -DCMAKE_IGNORE_PREFIX_PATH='/opt/homebrew;/usr/local' \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TESTING=OFF \
        -DESPEAK_BUILD_MANPAGES=OFF \
        -DUSE_LIBPCAUDIO=OFF \
        -DUSE_MBROLA=OFF

    cmake --build "$build_dir" --parallel "$(sysctl -n hw.ncpu)"
    cmake --install "$build_dir" --prefix "$install_dir"
}

# Make the program load libespeak-ng.dylib from its own folder, so the package works from anywhere.
#
# The upstream build links the program to @rpath/libespeak-ng.<major>.dylib and points the rpath at the
# install folder. This renames the library to libespeak-ng.dylib, points the rpath at the program's own
# folder, and signs both again (ad hoc), since changing a binary breaks its signature.
make_relocatable() {
    local package_dir="$1"
    local program="$package_dir/espeak-ng"
    local library="$package_dir/libespeak-ng.dylib"
    local old_name binary rpath

    old_name="$(otool -D "$library" | tail -n 1)"

    install_name_tool -id '@rpath/libespeak-ng.dylib' "$library"
    install_name_tool -change "$old_name" '@rpath/libespeak-ng.dylib' "$program"

    for binary in "$program" "$library"; do
        while read -r rpath; do
            install_name_tool -delete_rpath "$rpath" "$binary"
        done < <(get_rpaths "$binary")
    done

    install_name_tool -add_rpath '@executable_path' "$program"

    codesign --force --sign - "$library" "$program"
}

# Print the rpaths a binary searches for its libraries, one per line.
get_rpaths() {
    otool -l "$1" | awk '$1 == "cmd" && $2 == "LC_RPATH" {
        getline
        getline
        sub(/^ *path /, "")
        sub(/ \(offset [0-9]+\)$/, "")
        print
    }'
}

# Check the program and library only use system libraries, each other, and no path outside the package.
check_dependencies() {
    local package_dir="$1"
    local binary dependency

    for binary in "$package_dir/espeak-ng" "$package_dir/libespeak-ng.dylib"; do
        # The first line is the binary's own path, and for the library the second is its own install name.
        while read -r dependency; do
            case "$dependency" in
                /usr/lib/* | /System/* | '@rpath/libespeak-ng.dylib') ;;
                *)
                    echo "$(basename "$binary") depends on $dependency, which is not in the package" >&2
                    exit 1
                    ;;
            esac
        done < <(otool -L "$binary" | tail -n +2 | awk '{ print $1 }')
    done

    local rpaths
    rpaths="$(get_rpaths "$package_dir/espeak-ng")"

    if [[ "$rpaths" != '@executable_path' ]]; then
        echo "espeak-ng has unexpected rpaths: $rpaths" >&2
        exit 1
    fi
}

# Write NOTICE.txt, which says what is in the package, where it came from, and under which licenses.
write_notice() {
    local config="$1" path="$2"
    local version source_url other_licenses

    version="$(jq -r .version "$config")"
    source_url="$(jq -r .sourceUrl "$config")"
    other_licenses="$(jq -r '[.licenseFiles[] | select(. != "COPYING")] | join(", ")' "$config")"

    cat > "$path" <<EOF
eSpeak NG $version for macOS (Apple silicon)

This folder contains eSpeak NG $version, built from the unmodified upstream source so it runs from any
folder without installation. It needs macOS $deployment_target or later.

espeak-ng, libespeak-ng.dylib, espeak-ng-data/
    eSpeak NG, licensed under the GNU General Public License v3.0 or later (see COPYING).
    Some parts are under other licenses: see $other_licenses.
    Source code: $source_url

    The library includes sonic (https://github.com/waywardgeek/sonic), at the commit pinned by the
    eSpeak NG source, under the Apache License 2.0 (see COPYING.APACHE).

    Built without audio playback: write audio to a file with -w <file.wav>, or to stdout with --stdout.

Usage
    ./espeak-ng --path="<this folder>" [options]

    Always pass --path so the bundled data is used instead of an installed copy.
EOF
}

# Check the packaged program runs from its folder and converts a known phrase to the expected phonemes.
test_package() {
    local package_dir="$1" work_dir="$2"
    local input_file="$work_dir/smoke-test.txt"
    local expected='həlˈoʊ wˈɜːld'
    local output phonemes

    printf 'hello world' > "$input_file"

    output="$("$package_dir/espeak-ng" "--path=$package_dir" -q --ipa -v en-us -b 1 -f "$input_file")"

    # Join the lines and trim the spaces around them.
    phonemes="$(printf '%s' "$output" | tr '\n' ' ' | sed -E 's/^ +| +$//g')"

    if [[ "$phonemes" != "$expected" ]]; then
        echo "Smoke test failed: expected '$expected', got '$phonemes'" >&2
        exit 1
    fi

    echo "Smoke test passed: 'hello world' -> $phonemes"
}

# Build --------------------------------------------------------------------------------------------

check_arch

config="$repo_root/espeak-ng.json"
version="$(jq -r .version "$config")"
source_url="$(jq -r .sourceUrl "$config")"

mkdir -p "$output_dir" "$work_dir"

output_dir="$(cd "$output_dir" && pwd)"
work_dir="$(cd "$work_dir" && pwd)"

source_archive="$work_dir/espeak-ng-$version-source.tar.gz"
source_dir="$work_dir/source"

echo "Downloading $source_url"
curl --fail --location --silent --show-error --output "$source_archive" "$source_url"

rm -rf "$source_dir"
mkdir -p "$source_dir"
tar -xzf "$source_archive" -C "$source_dir" --strip-components 1

install_dir="$work_dir/install"

build_espeak "$source_dir" "$work_dir/build" "$install_dir"

package_dir="$work_dir/espeak-ng"

rm -rf "$package_dir"
mkdir -p "$package_dir"

cp "$install_dir/bin/espeak-ng" "$package_dir/"
cp -L "$install_dir/lib/libespeak-ng.dylib" "$package_dir/libespeak-ng.dylib"
cp -R "$install_dir/share/espeak-ng-data" "$package_dir/"

make_relocatable "$package_dir"
check_dependencies "$package_dir"

while read -r file; do
    cp "$source_dir/$file" "$package_dir/"
done < <(jq -r '.licenseFiles[]' "$config")

write_notice "$config" "$package_dir/NOTICE.txt"

test_package "$package_dir" "$work_dir"

zip_path="$output_dir/espeak-ng-$version-macos-arm64.zip"

rm -f "$zip_path"
(cd "$work_dir" && zip -q -r -X "$zip_path" espeak-ng)

zip_hash="$(shasum -a 256 "$zip_path" | awk '{ print $1 }')"

echo "Created $zip_path"
echo "SHA-256 $zip_hash"
