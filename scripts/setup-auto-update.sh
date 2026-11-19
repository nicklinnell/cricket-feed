#!/bin/zsh
# One-time setup: after any merge or commit on main, rebuild and reinstall
# CricketFeed.app in /Applications automatically.
# Undo: ./scripts/setup-auto-update.sh --off
set -euo pipefail
HOOKS="$(git rev-parse --git-common-dir)/hooks"
HOOKS="${HOOKS:A}"
MARK="# cricketfeed-auto-update"

for name in post-merge post-commit; do
    f="$HOOKS/$name"
    if [[ "${1:-}" == --off ]]; then
        [[ -f "$f" ]] && grep -q "$MARK" "$f" && rm "$f" && echo "Removed $f"
        continue
    fi
    if [[ -f "$f" ]] && ! grep -q "$MARK" "$f"; then
        echo "$f already exists and isn't ours. Skipping it." >&2
        continue
    fi
    cat > "$f" <<HOOK
#!/bin/sh
$MARK
s="\$(git rev-parse --show-toplevel)/scripts/hooks/auto-install.sh"
[ -x "\$s" ] && exec "\$s"
exit 0
HOOK
    chmod +x "$f"
    echo "Installed $f"
done
