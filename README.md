# dev

Native macOS workspace for reviewing GitHub projects. The app fetches repositories from GitHub after Device Flow sign-in and supports creating PRs from pushed branches, comments, reviews, and confirmed merges when the GitHub App has Pull requests: write permission. The sidebar shows each project’s open PR count. The app does not push local branches. Add the registered GitHub App client ID to `Config/GitHub.xcconfig` and enable Device Flow in the App settings before signing in. The current client ID is intentionally blank.

## Open and run

Open `dev.xcodeproj` in Xcode 27 or build/run the shared scheme:

```sh
xcodebuild build -project dev.xcodeproj -scheme dev -destination 'platform=macOS'
```

## Install in your Applications folder

This creates a local ad-hoc signed build and installs it for your macOS user (no administrator password):

```sh
xcodebuild build -project dev.xcodeproj -scheme dev -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
ditto build/DerivedData/Build/Products/Debug/dev.app ~/Applications/dev.app
open ~/Applications/dev.app
```

Afterward, launch **dev** from Spotlight or Finder → Home → Applications. The empty workspace offers **Sign in with GitHub**; signing in requires the registered client ID in `Config/GitHub.xcconfig` and Device Flow enabled. No sample repositories are shown.

## Checks

```sh
xcodebuild test -project dev.xcodeproj -scheme dev -destination 'platform=macOS'
python3 -m unittest discover -s Tests/DocSec -v
python3 Scripts/docsec.py
```

The last command is expected to report incomplete while v1 requirements remain unimplemented. DocSec checks that the status ledger matches the product acceptance criteria and that completion claims name evidence; it cannot prove those claims.

## Project map

- `App/` — SwiftUI app shell, GitHub REST and Device Flow services, Keychain token storage, and workspace state.
- `Config/GitHub.xcconfig` — public GitHub App client ID build setting (currently blank).
- `AppTests/` — Swift Testing unit tests.
- `AppUITests/` — macOS UI flow tests.
- `Scripts/docsec.py` — documentation completion gate.
- `Tests/DocSec/` — DocSec unit tests.

The three product documents and this repository's `AGENTS.md` provide the shared, persistent contract for all implementation agents.
