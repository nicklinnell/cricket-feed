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
TARGET="$DEST/$APP_NAME"
# Normal case: swap the whole app in DEST.
# If DEST isn't writable (e.g. /Applications for a non-admin user) but you own
# the installed app, update it in place by swapping its Contents folder instead.
if [[ -w "$DEST" ]]; then
    IN_PLACE=0
elif [[ -d "$TARGET" && ! -L "$TARGET" && -w "$TARGET" ]]; then
    IN_PLACE=1
else
    echo "Can't write to: $DEST" >&2
    exit 1
fi
if [[ "$DEST" == "$REPO/build" ]]; then
    echo "Pick a folder other than the build folder." >&2
    exit 1
fi

./scripts/build-app.sh

# Private work folder per run, next to what we replace, so the final swap is a same-disk rename.
if (( IN_PLACE )); then
    WORK="$(mktemp -d "$TARGET/.install.XXXXXX")"
    REPLACE="$TARGET/Contents"
    STAGE="$WORK/$APP_NAME/Contents"
    OLD="$WORK/old-Contents"
else
    WORK="$(mktemp -d "$DEST/.CricketFeed-install.XXXXXX")"
    REPLACE="$TARGET"
    STAGE="$WORK/$APP_NAME"
    OLD="$WORK/old.app"
fi
cleanup() {
    # If we stopped between the two moves, put the old one back.
    if [[ ! -e "$REPLACE" && ! -L "$REPLACE" ]] && [[ -e "$OLD" || -L "$OLD" ]]; then
        if ! mv "$OLD" "$REPLACE"; then
            echo "Old copy left at $OLD" >&2
            return
        fi
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Copy next to the target first, so a failed copy leaves the old app alone.
# ditto keeps the code signature and bundle metadata intact.
ditto "build/$APP_NAME" "$WORK/$APP_NAME"
codesign --verify --strict "$WORK/$APP_NAME"

# Quit the installed copy (only that one, not a dev build) so we can swap it.
# Done after the build, so a failed build leaves the old app running.
EXE="$TARGET/Contents/MacOS/CricketFeed"
WAS_RUNNING=0
if pkill -TERM -xf "$EXE" 2>/dev/null; then
    WAS_RUNNING=1
    for _ in {1..50}; do pgrep -xf "$EXE" >/dev/null || break; sleep 0.1; done
    pkill -KILL -xf "$EXE" 2>/dev/null || true
fi

if [[ -e "$REPLACE" || -L "$REPLACE" ]]; then
    mv "$REPLACE" "$OLD"
fi
mv "$STAGE" "$REPLACE"
# In place, the work folder sits inside the app; remove it before checking the signature.
(( IN_PLACE )) && rm -rf "$WORK"
# Catch a clash with another install running at the same time.
codesign --verify --strict "$TARGET"

# Tell Finder/Launchpad about the new bundle so the icon shows straight away.
# Only for real app folders, so test installs don't pile up in macOS's app list.
if [[ "$DEST" == /Applications || "$DEST" == "$HOME/Applications" ]]; then
    LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    [[ -x "$LSREG" ]] && "$LSREG" -f "$TARGET" >/dev/null 2>&1 || true
fi
touch "$TARGET"

echo "Installed $TARGET"
if (( WAS_RUNNING )); then
    open "$TARGET"
    echo "Restarted it."
else
    echo "Open it with: open \"$TARGET\""
fi
