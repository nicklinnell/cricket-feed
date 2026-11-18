#!/bin/zsh
# Builds CricketFeed.app and copies it into /Applications.
# Usage: ./scripts/install.sh [destination folder]   (default /Applications)
set -euo pipefail

if (( $# > 0 )) && [[ -z "$1" ]]; then
    echo "Destination folder is empty." >&2
    exit 1
fi
# Make the destination a real absolute path (symlinks resolved) before we cd into the repo.
DEST="${${1:-/Applications}:P}"
APP_NAME=CricketFeed.app

cd "$(dirname "$0")/.."
REPO="${PWD:P}"

if [[ ! -d "$DEST" ]]; then
    echo "No such folder: $DEST" >&2
    exit 1
fi
if [[ ! -w "$DEST" ]]; then
    echo "Can't write to: $DEST" >&2
    exit 1
fi
if [[ "$DEST" == "$REPO/build" ]]; then
    echo "Pick a folder other than the build folder." >&2
    exit 1
fi

./scripts/build-app.sh

TARGET="$DEST/$APP_NAME"
# Private work folder per run, next to the target, so the final swap is a same-disk rename.
WORK="$(mktemp -d "$DEST/.CricketFeed-install.XXXXXX")"
STAGE="$WORK/$APP_NAME"
OLD="$WORK/old.app"
cleanup() {
    # If we stopped between the two moves, put the old app back.
    if [[ ! -e "$TARGET" && -e "$OLD" ]]; then
        if ! mv "$OLD" "$TARGET"; then
            echo "Old app left at $OLD" >&2
            return
        fi
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Copy next to the target first, so a failed copy leaves the old app alone.
# ditto keeps the code signature and bundle metadata intact.
ditto "build/$APP_NAME" "$STAGE"
codesign --verify --strict "$STAGE"

if [[ -e "$TARGET" ]]; then
    mv "$TARGET" "$OLD"
fi
mv "$STAGE" "$TARGET"

# Tell Finder/Launchpad about the new bundle so the icon shows straight away.
# Only for real app folders, so test installs don't pile up in macOS's app list.
if [[ "$DEST" == /Applications || "$DEST" == "$HOME/Applications" ]]; then
    LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    [[ -x "$LSREG" ]] && "$LSREG" -f "$TARGET" >/dev/null 2>&1 || true
fi
touch "$TARGET"

echo "Installed $TARGET"
echo "Open it with: open \"$TARGET\""
echo "If an older copy is running, quit it from the menu bar icon first, then reopen."
