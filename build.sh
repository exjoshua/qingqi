#!/bin/zsh
set -eu
source_dir=${0:A:h}
build_dir="$source_dir/build"
mkdir -p "$build_dir"
output="$build_dir/轻启.app"
staging=$(mktemp -d "$build_dir/.qingqi-build.XXXXXX")
trap 'rm -rf "$staging"' EXIT
bundle="$staging/轻启.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$staging/Qingqi.iconset"
xcrun swiftc -O -target "$(uname -m)-apple-macos13.0" "$source_dir"/Sources/*.swift -o "$bundle/Contents/MacOS/Qingqi"
cp "$source_dir/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$source_dir/Resources/MenuBar/跃点.pdf" "$bundle/Contents/Resources/MenuBarIcon.pdf"
xcrun swift "$source_dir/Resources/MakeIcon.swift" "$staging/Qingqi.iconset"
iconutil -c icns "$staging/Qingqi.iconset" -o "$bundle/Contents/Resources/Qingqi.icns"
codesign --force --sign - --identifier local.qingqi.launcher "$bundle"
# Replace the directory as a unit so a live process keeps its mapped executable.
if [[ -e "$output" ]]; then
    xcrun swift - "$bundle" "$output" <<'SWIFT'
import Darwin
if renamex_np(CommandLine.arguments[1], CommandLine.arguments[2], UInt32(RENAME_SWAP)) != 0 {
    perror("replace app")
    exit(1)
}
SWIFT
else
    mv "$bundle" "$output"
fi
echo "$output"
