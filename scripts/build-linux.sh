#!/bin/bash
# Builds build/loopsmith-linux-<arch>.tar.gz: the `loopsmith` command as one static binary (musl), which runs on any
# Linux distribution with no dependency. Needs Swift 6.2.4 on Linux, e.g. in the swift:6.2.4-noble image:
#   docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble ./scripts/build-linux.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# The static Linux SDK must match the toolchain exactly.
SWIFT_VERSION="6.2.4"
SDK_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/static-sdk/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz"
SDK_SHA256="24bdf84495dd31a6de2eb679647c1982b747bfbfe1a2060c779d84dcecd902a4"

case "$(uname -m)" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if ! swift --version 2>&1 | grep -q "Swift version ${SWIFT_VERSION} "; then
  echo "This script needs Swift ${SWIFT_VERSION} (found: $(swift --version 2>&1 | head -1))." >&2
  exit 1
fi
if ! swift sdk list 2>/dev/null | grep -q "swift-${SWIFT_VERSION}-RELEASE_static-linux"; then
  swift sdk install "$SDK_URL" --checksum "$SDK_SHA256"
fi

SDK="${ARCH}-swift-linux-musl"
# -s strips the symbols at link time: 60 MB instead of 170.
swift build -c release --swift-sdk "$SDK" -Xlinker -s
BIN="$(swift build -c release --swift-sdk "$SDK" -Xlinker -s --show-bin-path)/Loopsmith"

mkdir -p build/linux
cp "$BIN" build/linux/loopsmith
tar -C build/linux -czf "build/loopsmith-linux-${ARCH}.tar.gz" loopsmith
echo "Built build/loopsmith-linux-${ARCH}.tar.gz ($(du -h build/linux/loopsmith | cut -f1))"
