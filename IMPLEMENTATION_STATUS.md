# Implementation Status

DocSec mirrors the Product Requirements acceptance criteria in order and checks that each completed item has an evidence reference. A checked row is an evidence claim, not independent proof. Keep this ledger current and link to an automated test, build result, or reviewed implementation for every completion claim.

## Acceptance criteria
- [ ] AC-01 — A first-run user can authorize GitHub and see accessible personal and organization repositories; permission and installation gaps are explained with a recovery path. Evidence: pending
- [ ] AC-02 — The repository list is paginated and does not claim to show a repository that GitHub has not exposed to the authorized app. Evidence: pending
- [ ] AC-03 — The user can choose a parent folder and clone a selected repository under its repository name. Existing/non-empty target paths are protected from overwrite. Evidence: pending
- [ ] AC-04 — The project view distinguishes GitHub remote branches/commits from local branches, working-tree state, and linked worktrees. Evidence: pending
- [ ] AC-05 — The branch graph can navigate to the related commit and, where available, PR/merge record. Deleted remote branches remain visible as historical PR/merge records when GitHub still exposes that data. Evidence: pending
- [ ] AC-06 — PR detail includes all fields listed in the scope, with links to the authoritative GitHub page. Evidence: pending
- [ ] AC-07 — Issues, contributor identities, and recent items show loading, empty, stale, and access-error states distinctly. Evidence: pending
- [ ] AC-08 — Preview links require a user click and open only recognized web URLs in the system browser. Evidence: pending
- [ ] AC-09 — New/changed PR detection covers all accessible repositories by default, runs on foreground and the configured polling schedule while the app is running, and shows per-repository stale state and rate-limit delays. Full PR details load on demand. Evidence: pending
- [ ] AC-10 — No v1 action writes to GitHub. Clone/fetch are read operations against GitHub; local cloning writes only under the user-selected destination. Evidence: pending
- [ ] AC-11 — Any enabled AI explanation identifies its source records. AI is unavailable until its provider/data-handling choice and consent flow are defined. Evidence: pending
- [x] AC-12 — The navigation consistently presents repositories as projects, with distinct cross-project **All Projects** and **Activity** destinations and project-specific **Overview**, **Branches**, **Commits**, **Pull Requests**, and **Issues** destinations. Evidence: `xcodebuild test` UI flows `testUserCanOpenProjectAndMoveThroughWorkspaceDestinations` and `testSidebarOpensActivityAndSettings`; 2026-10-30.
- [ ] AC-13 — The interface targets the latest macOS release supported at implementation and remains usable with keyboard navigation, VoiceOver labels, and system appearance settings. Evidence: pending

## Verification gates
- [x] Build — Evidence: `xcodebuild build -project dev.xcodeproj -scheme dev -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`; installed bundle signature verified, macOS 26.6.2, 2026-10-30.
- [x] Unit tests — Evidence: 6 Swift Testing backend tests passed in `/tmp/dev-signin-header.xcresult`; 3 DocSec tests passed with `python3 -m unittest discover -s Tests/DocSec -v`, 2026-10-30.
- [x] End-to-end — Evidence: 2 macOS XCTest UI flows passed in `/tmp/dev-signin-header.xcresult`, including the Sign in with GitHub action, inline missing-client-ID guidance, no sample rows, and sidebar navigation, 2026-10-30.
