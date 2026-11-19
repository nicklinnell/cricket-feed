<img src="assets/icon-1024.png" width="96" height="96" alt="">

# cricinfo-feed

Small macOS app. Floating window, always on top, shows live scores for the cricket matches you pick.

## Build and run

```sh
./scripts/build-app.sh
open build/CricketFeed.app
```

## Install

```sh
./scripts/install.sh
```

Builds the app and copies it into `/Applications`. Run it again to update. If you can't write to `/Applications` but own the installed app, it updates the app in place. If the app is running, it gets restarted on the new version.

### Auto-update

```sh
./scripts/setup-auto-update.sh
```

One-time setup. After that, every merge or commit on `main` rebuilds and reinstalls the app in the background, then restarts it if it was open. You get a notification when it's done or if it fails. Log: `~/Library/Logs/CricketFeed-install.log`.

This adds `post-merge` and `post-commit` hooks to the repo's shared git hooks folder, so it covers every worktree. It only acts on `main`. Turn it off with `./scripts/setup-auto-update.sh --off`.

The icon is `assets/icon-1024.png`. The build turns it into `AppIcon.icns`.

## Use

- Press `+` to pick matches. Press Done when finished.
- Press the star to choose favourite teams (countries, English counties, or any team in the feed). Their matches sit at the top of the match list and the panel. With "Auto-watch my teams' matches" on (the default), they also show up without being picked.
- Drag the window anywhere to move it.
- Right-click a match to open it on Cricinfo or stop watching it. A stopped match stays stopped until you tick it again in the match list.
- Menu bar icon: show/hide window, quit. There's no Dock icon.
- Scores refresh every 10 seconds.

## Data source

Uses ESPN's unofficial score feed (ESPN owns Cricinfo):
`https://site.api.espn.com/apis/site/v2/sports/cricket/scorepanel`

No key or login needed. It isn't documented, so it may change or stop working without notice. Match IDs match Cricinfo's.
