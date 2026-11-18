#!/bin/zsh
# Builds CricketFeed.app and copies it into /Applications.
# Usage: ./scripts/install.sh [destination folder]   (default /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-/Applications}"
APP_NAME=CricketFeed.app

if [[ ! -d "$DEST" ]]; then
    echo "No such folder: $DEST" >&2
    exit 1
fi

./scripts/build-app.sh

TARGET="$DEST/$APP_NAME"
if [[ -e "$TARGET" ]]; then
    rm -rf "$TARGET"
fi
# ditto keeps the code signature and bundle metadata intact.
ditto "build/$APP_NAME" "$TARGET"

# Tell Finder/Launchpad about the new bundle so the icon shows straight away.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREG" ]] && "$LSREG" -f "$TARGET" >/dev/null 2>&1 || true
touch "$TARGET"

echo "Installed $TARGET"
echo "Open it with: open \"$TARGET\""
echo "If an older copy is running, quit it from the menu bar icon first, then reopen."
