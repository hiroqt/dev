# Agent Instructions

## Project status
- `dev` has a native SwiftUI shell and direct GitHub Device Flow/repository backend. Live account requests require the registered GitHub App client ID in `Config/GitHub.xcconfig` and Device Flow enabled in GitHub settings.
- Follow `PRODUCT_REQUIREMENTS.md`, `ARCHITECTURAL_REQUIREMENTS.md`, and `END_TO_END_FLOW.md` as the v1 contract. Raise conflicts before expanding scope.

## Platform and boundaries
- Build a native macOS app in Swift with SwiftUI; use native frameworks before adding dependencies.
- GitHub v1 access is read-only. Do not add write permissions or GitHub mutations without a revised product decision.
- Local clone/fetch may write only under the user-selected clone destination. Never overwrite/delete existing user data automatically.
- Keep GitHub tokens in Keychain. Never put secrets in URLs, process arguments, Git remotes, logs, or crash output.
- AI is gated on provider and explicit data consent. Do not send local source files, credentials, or unselected repository data to a model.
- Treat AI output as untrusted and attach GitHub evidence links to repository-specific claims.
- Preview links require a user action and HTTP(S) validation; open them in the system browser.

## Architecture conventions
- Keep SwiftUI views separate from GitHub REST, local Git, persistence, polling, and AI adapters.
- Use cancellable async work; keep network and Git subprocess work off the main actor.
- Invoke Git with argument arrays, never a shell-interpolated command; redact process output before presentation/logging.
- Label remote GitHub state, local clone state, and cached/stale data separately.
- Preserve partial clones and cached data on errors; never infer missing remote data as deletion without confirming access and pagination.

## Commands
- Open `dev.xcodeproj` in Xcode 27. Build with `xcodebuild build -project dev.xcodeproj -scheme dev -destination 'platform=macOS'`.
- Run app unit and macOS UI flow tests with `xcodebuild test -project dev.xcodeproj -scheme dev -destination 'platform=macOS'`.
- Run DocSec tests with `python3 -m unittest discover -s Tests/DocSec -v`; run the completion gate with `python3 Scripts/docsec.py` (expected to report incomplete until all product criteria have evidence).

## Git and commits
- Preserve unrelated user changes; stage only task files. Do not commit unless requested or required by the project workflow.
- If an AI-authored commit is requested, use the configured truthful agent attribution; do not invent an identity.

## Persistent agent workflow
- Use this file as the single shared instruction entry point for every agent working in this repository. Start with `PRODUCT_REQUIREMENTS.md`, `ARCHITECTURAL_REQUIREMENTS.md`, and `END_TO_END_FLOW.md`; they define one product contract.
- Before claiming a requirement is done, update `IMPLEMENTATION_STATUS.md` with reviewed evidence and run `python3 Scripts/docsec.py`. DocSec checks documentation coverage and evidence bookkeeping; it does not prove behavior or replace tests and review.
- Run `xcodebuild test -project dev.xcodeproj -scheme dev -destination 'platform=macOS'` for app and UI flow changes, and `python3 -m unittest discover -s Tests/DocSec -v` for DocSec changes.
- Agents may suggest improvements to this workflow, but must not silently rewrite the product contract, security boundaries, or these shared rules. Put proposed lessons in the task summary for coordinator review.
