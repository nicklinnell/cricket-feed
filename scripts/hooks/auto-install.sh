#!/bin/zsh
# Called by git hooks (post-merge, post-commit). When main changes, rebuilds
# and reinstalls CricketFeed.app in /Applications in the background.
# Log: ~/Library/Logs/CricketFeed-install.log
set -uo pipefail

# Hooks are shared by every worktree. Only act on main.
[[ "$(git symbolic-ref --short -q HEAD)" == main ]] || exit 0

REPO="$(git rev-parse --show-toplevel)"
STATE="$(git rev-parse --git-common-dir)"
STATE="${STATE:A}"
LOG="$HOME/Library/Logs/CricketFeed-install.log"
LOCK="$STATE/cricketfeed-install.lock"

# Don't let git's hook settings leak into the build.
for v in ${(k)parameters[(I)GIT_*]}; do unset $v; done

notify() {
    osascript -e "display notification \"$1\" with title \"Cricket Feed\"" >/dev/null 2>&1 || true
}

worker() {
    mkdir "$LOCK" 2>/dev/null || exit 0   # another run is busy; it re-checks main when done
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT
    local done_file="$STATE/cricketfeed-installed-sha"
    while true; do
        local sha="$(git -C "$REPO" rev-parse main)"
        [[ -f "$done_file" && "$(<"$done_file")" == "$sha" ]] && break
        echo "=== $(date '+%F %T') installing ${sha[1,7]}"
        if "$REPO/scripts/install.sh" ${CRICKETFEED_DEST:+"$CRICKETFEED_DEST"}; then
            echo "$sha" > "$done_file"
            notify "Updated to ${sha[1,7]}"
        else
            notify "Update failed. See ~/Library/Logs/CricketFeed-install.log"
            break
        fi
    done
}

# Run detached so git returns straight away.
worker </dev/null >>"$LOG" 2>&1 &!
exit 0
