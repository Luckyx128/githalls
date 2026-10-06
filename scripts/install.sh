#!/usr/bin/env bash
# Builds GitHalls in Release and installs it to /Applications.
#
# Usage: scripts/install.sh [--no-open]
set -euo pipefail

open_after=1
for arg in "$@"; do
    case "$arg" in
        --no-open) open_after=0 ;;
        -h|--help) echo "Usage: $0 [--no-open]"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

# Work from the repo root no matter where the script is invoked from.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

dest="/Applications/GitHalls.app"
built="build/Build/Products/Release/GitHalls.app"

echo "Building GitHalls (Release)..."
xcodebuild -scheme GitHalls -configuration Release -destination 'platform=macOS' \
    -derivedDataPath build -quiet build

[[ -d "$built" ]] || { echo "Build output not found: $built" >&2; exit 1; }

if pgrep -x GitHalls >/dev/null; then
    echo "Quitting running GitHalls..."
    osascript -e 'quit app "GitHalls"' >/dev/null 2>&1 || true
    for _ in $(seq 1 50); do
        pgrep -x GitHalls >/dev/null || break
        sleep 0.2
    done
    if pgrep -x GitHalls >/dev/null; then
        echo "GitHalls did not quit; close it and run again." >&2
        exit 1
    fi
fi

echo "Installing to $dest..."
rm -rf "$dest"
cp -R "$built" "$dest"

if [[ "$open_after" -eq 1 ]]; then
    open "$dest"
fi
echo "Done."
