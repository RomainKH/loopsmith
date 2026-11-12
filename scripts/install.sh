#!/bin/sh
# Installs Loopsmith from its GitHub release:
#   macOS: Loopsmith.app in /Applications (or ~/Applications) and the `loopsmith` command
#   Linux: the `loopsmith` command (one static binary). Windows: run it in WSL.
#
#   curl -fsSL https://raw.githubusercontent.com/RomainKH/loopsmith/main/scripts/install.sh | sh
#
# LOOPSMITH_VERSION=0.2.0   a given release instead of the latest
# LOOPSMITH_BIN_DIR=...     where the command goes (default ~/.local/bin)
# LOOPSMITH_APP_DIR=...     where the app goes on macOS (default /Applications, else ~/Applications)
# LOOPSMITH_ARCHIVE=...     install a release archive already on disk (no download, no checksum)
set -eu

REPO="${LOOPSMITH_REPO:-RomainKH/loopsmith}"
VERSION="${LOOPSMITH_VERSION:-latest}"
BIN_DIR="${LOOPSMITH_BIN_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*"; }
fail() { printf 'loopsmith install: %s\n' "$*" >&2; exit 1; }

if [ "$VERSION" = "latest" ]; then
  BASE="https://github.com/$REPO/releases/latest/download"
else
  BASE="https://github.com/$REPO/releases/download/v${VERSION#v}"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

# Downloads a release asset and checks it against the release's SHA256SUMS.
fetch() {
  asset="$1"
  if [ -n "${LOOPSMITH_ARCHIVE:-}" ]; then
    cp "$LOOPSMITH_ARCHIVE" "$TMP/$asset"
    return
  fi
  command -v curl >/dev/null 2>&1 || fail "curl is needed"
  say "Downloading $asset ($VERSION)…"
  curl -fsSL --retry 3 -o "$TMP/$asset" "$BASE/$asset" || fail "could not download $BASE/$asset"
  curl -fsSL --retry 3 -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" || fail "could not download the checksums"
  expected="$(grep " $asset\$" "$TMP/SHA256SUMS" | cut -d' ' -f1)"
  [ -n "$expected" ] || fail "$asset is not in SHA256SUMS"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$TMP/$asset" | cut -d' ' -f1)"
  else
    actual="$(shasum -a 256 "$TMP/$asset" | cut -d' ' -f1)"
  fi
  [ "$expected" = "$actual" ] || fail "checksum mismatch for $asset"
}

mkdir -p "$BIN_DIR"

case "$(uname -s)" in
  Darwin)
    major="$(sw_vers -productVersion | cut -d. -f1)"
    [ "$major" -ge 14 ] || fail "Loopsmith needs macOS 14 or later"
    fetch Loopsmith-macos.zip
    ditto -x -k "$TMP/Loopsmith-macos.zip" "$TMP/app"
    APP_DIR="${LOOPSMITH_APP_DIR:-/Applications}"
    if [ -z "${LOOPSMITH_APP_DIR:-}" ] && [ ! -w "$APP_DIR" ]; then APP_DIR="$HOME/Applications"; fi
    mkdir -p "$APP_DIR"
    rm -rf "$APP_DIR/Loopsmith.app"
    mv "$TMP/app/Loopsmith.app" "$APP_DIR/"
    # The app is not notarized: without this, a browser download would make macOS refuse to open it.
    xattr -dr com.apple.quarantine "$APP_DIR/Loopsmith.app" 2>/dev/null || true
    ln -sf "$APP_DIR/Loopsmith.app/Contents/MacOS/Loopsmith" "$BIN_DIR/loopsmith"
    say "Installed $APP_DIR/Loopsmith.app and $BIN_DIR/loopsmith"
    ;;
  Linux)
    case "$(uname -m)" in
      x86_64|amd64) ARCH="x86_64" ;;
      aarch64|arm64) ARCH="aarch64" ;;
      *) fail "no Linux build for $(uname -m): build it from source (see the README)" ;;
    esac
    fetch "loopsmith-linux-$ARCH.tar.gz"
    tar -xzf "$TMP/loopsmith-linux-$ARCH.tar.gz" -C "$TMP"
    install -m 0755 "$TMP/loopsmith" "$BIN_DIR/loopsmith"
    say "Installed $BIN_DIR/loopsmith"
    if grep -qi microsoft /proc/version 2>/dev/null; then
      say "WSL detected: run the agents' CLIs, git and gh inside WSL too."
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    fail "on Windows, install WSL (wsl --install), then run this command in its Ubuntu terminal"
    ;;
  *)
    fail "unsupported system: $(uname -s)"
    ;;
esac

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "Add $BIN_DIR to your PATH, e.g.: echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.profile" ;;
esac

say ""
missing=0
for tool in git gh claude; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing=1
    case "$tool" in
      git) say "• git is missing: install it with your package manager." ;;
      gh) say "• The GitHub CLI (gh) is missing, for pull requests: https://cli.github.com, then gh auth login" ;;
      claude) say "• Claude Code is missing, the agent CLI (also used for local models): curl -fsSL https://claude.ai/install.sh | bash" ;;
    esac
  fi
done
[ "$missing" = 0 ] && say "git, gh and claude are installed."
say ""
say "Next: loopsmith add <your repository>, then loopsmith new \"<what to build>\" (loopsmith help lists everything)."
if [ "$(uname -s)" = "Darwin" ]; then say "Or open Loopsmith from your Applications folder."; fi
