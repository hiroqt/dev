# dev

Native macOS workspace for reviewing GitHub projects. The app fetches repositories from GitHub after Device Flow sign-in and supports creating PRs from pushed branches, comments, reviews, and confirmed merges when the GitHub App has Pull requests: write permission. The sidebar shows each project’s open PR count. The app does not push local branches. Add the registered GitHub App client ID to `Config/GitHub.xcconfig` and enable Device Flow in the App settings before signing in. The current client ID is intentionally blank.

The project tool panel can launch locally installed Codex (`codex`), Antigravity (`agy`), and Claude Code (`claude`) CLIs. Enable providers globally in Settings and per project in the tool launcher. The sidebar and Quick Summary show per-provider usage: Antigravity uses structured CLI quota/credit output, Codex reads the local app-server's structured plan and rate-limit response, and Claude links to its provider usage screen and shows Unavailable in dev. Usage snapshots remain in memory; user-entered plan labels never determine limits.

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

## Monitoring

Open **Monitoring** in either sidebar mode. Choose **Server / Deployment** for hosting connections and uptime, **Computer** for CPU, RAM, swap, disk and network charts, or **AI** for subscription quotas and API usage/billing. Only the selected tab’s content is displayed. Local minute samples and user-added HTTPS HEAD availability checks retain seven days in Application Support/dev/Monitoring/history.json. Sampling runs while dev is running; sleep/closed intervals are gaps. Network excludes virtual interfaces. HTTP HEAD-incompatible services can report failed checks even when their GET endpoint works.

Connect Vercel/Render account tokens or OpenAI/Anthropic organization reporting credentials using the page’s secure field; credentials are saved only in macOS Keychain. Reads refresh every five minutes. Vercel discovers personal and team projects visible to the token with paginated reads and explicit access/truncation warnings. Browse the overview summary/recent-release rail and account-filtered project rows. Select a row to open a dedicated production overview with domains, source, numeric analytics and history; All projects returns to the saved project search/page. Previous/Next paginate six projects or five deployment rows at a time; older history loads only when needed. Render shows up to 20 accessible services. OpenAI token counts cover Completions, while costs cover organization API charges; Anthropic uses its Analytics beta. Partial results and stale reads are labeled. Subscription quotas reuse existing provider readers; Claude subscription usage is unavailable. Disconnect removes the connection credential. API billing reports stay in memory; metric/uptime history excludes HTTP bodies, prompts, source and secrets. No monitoring notifications or remote mutations are performed.

### Connect Vercel

1. Create an access token at [Vercel Tokens](https://vercel.com/account/tokens), scoped to the account/team owning your projects.
2. Open Monitoring → Server / Deployment, select Vercel, paste the token into the secure field and choose Save connection.
3. Search projects/teams and select a project row. Its history shows five deployments per page; select a row for details. Previous/Next reuse cached results and fetch another 20-record Vercel page only when needed. Refresh checks the newest history. Connection settings can be expanded to replace credentials.

Project discovery includes personal and accessible team scopes; revoked/denied scopes and bounded discovery limits remain visible. The token determines which projects can be seen. Seven-day browser pageviews/visitors use [Vercel Web Analytics](https://vercel.com/docs/rest-api/web-analytics/counts-page-views), require instrumentation and account access, and do not represent total network requests or bandwidth. Open Vercel Observability on a project for bandwidth, edge requests, errors, latency and other unsupported metrics, subject to Vercel plan/access. No drains or hosting settings are changed.

Project details include Observability, Web Analytics and Deployment Branches cards with real daily pageview charts when returned by Vercel, Observability links and searchable deployment branches from loaded history. Project icons come directly from each website’s declared raster logo/favicon over bounded HTTPS reads, without cookies or credentials. A globe appears if no supported icon is available. No site screenshots or scripts are loaded.

Computer also provides local process CPU/RAM inspection, battery information reported by macOS, and an on-demand app storage scan. Storage figures are measured metadata with partial-access limits, not a complete attribution of all disk use. Scanning does not delete files or send results to a service.

The battery card includes battery-level and estimated main-display screen-on charts on its right, with 24-hour/seven-day ranges. Samples are collected each minute while Computer is visible and kept locally in battery.json for seven days. Historical macOS Settings data is not imported; missing intervals are gaps. Screen-on usage is an estimate, not macOS Screen Time.
