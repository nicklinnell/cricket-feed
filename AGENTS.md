# AGENTS.md

macOS menu bar app (SwiftUI + AppKit, Swift package, macOS 14+). Floating panel with live cricket scores. `README.md` covers build, install and user-facing behaviour.

## Checking your work

- `swift test` must pass. Add a test when you change feed parsing, ball-by-ball figures or which matches get watched.
- Tests use inline JSON fixtures (`Tests/CricketFeedTests/Fixtures.swift`) and a throwaway `UserDefaults` suite. They never call ESPN or touch the user's settings.
- Put parsing in plain functions like `parseMatches` and `buildLiveDetail`, so tests can call them. The network call stays a thin wrapper.
- For UI changes, run `./scripts/build-app.sh` then `open build/CricketFeed.app` and look.
- Committing or merging on `main` rebuilds, reinstalls and restarts the user's installed app. The git hooks are shared by every worktree, see `scripts/hooks/auto-install.sh`. Work on a branch; land on `main` only when asked.

## Data feed

- ESPN's feed is unofficial and undocumented. Decode every field as optional and expect the shape to change. Team IDs already arrive as text or numbers, see `Team` in `Feed.swift`.
- Match teams by ESPN team ID, never by name. Every ID in `Teams.swift` was checked against ESPN's team records. Check new ones the same way.

## UI

- Use the sizes, colours and pieces in `Theme` (`Design.swift`). Keep text to its type scale.
- Check light and dark mode, Reduce Motion, and the panel height cap when changing layout.

## Persistence

User choices live in `UserDefaults` via `ScoreStore` (`Store.swift`). Keep existing keys stable so upgrades keep users' picks, favourites and hidden matches.

Open at Login is the exception: macOS keeps it (`LoginItem.swift`), so don't copy it into `UserDefaults`.

## Docs

Update `README.md` when user-facing behaviour or scripts change. Write in plain British English.
