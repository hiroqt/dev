# Workspace UI behavior

The repository browser uses an adaptive SwiftUI grid with a 320-point minimum card width. It adds columns as the content area grows and lets cards fill the available width, including in fullscreen. Project workspaces scroll vertically so long commit messages and pull request descriptions remain readable.

Selecting a commit shows its complete message and GitHub link immediately below that commit. Each commit message and pull request description can be expanded or minimized independently. Each offers **Preview** (formatted Markdown) and **Markdown** (raw source) buttons; Preview is the default. Preview lays out headings, paragraphs, lists, quotes, and fenced code separately while preserving inline emphasis and links. Links open only after a click and only when they use HTTP or HTTPS. GitHub timestamps use `MMM d, yyyy, h:mm a` in the current time zone; missing or unreadable timestamps display “Date unavailable.”

Project navigation controls use consistent insets and a minimum height, and reflow into additional rows when the window is narrow.

## Coding provider integrations

Settings controls global Codex, Antigravity, and Claude Code enablement and an optional account plan label. Plan choices are informational only. The selected project's tool launcher has separate per-project toggles, shows CLI availability and an official setup link when a CLI is missing, and launches an enabled CLI in a retained terminal tab rooted at that project. Provider sign-in remains with the provider: dev can explicitly run Codex's documented `codex login status` check, but Antigravity and Claude Code sign-in remain Unknown. Expandable per-provider usage rows appear in the sidebar and Quick Summary, including the expanded notch; the compact sidebar opens usage in a sheet. Antigravity uses the official read-only `/usage` and `/credits` JSON commands, refreshed on demand and every five minutes while enabled. Its current model quota/credit snapshot stays in memory. Codex usage uses the local app-server's structured rate-limit response when supported; Claude usage is Unavailable in dev and links to provider instructions. No interactive output is parsed, and plan labels do not infer limits.

The Overview card centers its heading, repository description, and history summary.

The sidebar shows the signed-in GitHub login. The app reads it from the authenticated, read-only GraphQL `viewer { login }` field. Sign out clears the displayed login with the local session state; no additional permission scope is needed.

## Skills library

The sidebar's **Skills** destination uses the same full-row click and selected-row treatment as other destinations. Its catalog and detail cards follow the global surface-opacity setting, and text follows the workspace font-size setting. Search inputs and primary actions have larger hit targets and spacing. The page searches the saved catalog offline by name, description/purpose, tags, and category. When the catalog is empty, it shows an explicit empty-state message and keeps the detail pane out of the layout. Narrow windows show one pane at a time; selecting a skill opens its detail with a Back to Skills control. The multiline command form resolves supported GitHub plugin and Skills CLI sources into separate import candidates. Successful clones scan for skill instruction files and offer GitHub skill links advertised from Markdown documents. The scan button repeats that work across registered clones.

Adding a local folder or a GitHub result stores regular files under Application Support, capped at 100 files, 2 MB per file, and 10 MB total. Hidden paths and symlinks are skipped. If a source disappears, its saved copy remains available and the detail view labels the source unavailable. Refresh replaces the source files but keeps a category the user changed. The preview renders UTF-8 text up to 2 MB; larger or binary files stay in the copy and are listed as unavailable.

The add form uses a multiline command editor for Codex, Claude Code, Copilot CLI, Gemini CLI, or `npx skills add` commands. Submit parses the text without running it, reads the referenced public GitHub repository/marketplace through GET requests, and shows matching skill files as import candidates. Named skill commands filter to the named skill; plugin commands resolve the plugin source from its marketplace manifest. Imported entries retain the submitted command and identify its tool as provenance. The detail view shows the source URL, stored path, tags, editable category, and an attributed install command when the source documents one or the Skills CLI command can be derived. Commands are copy-only and are never executed. Skill content and commands are treated as untrusted text and are not sent to an AI provider.

Command resolution and selected-source reads use GitHub GET requests; no GitHub permission or repository write is added.

## Verification

Run the macOS app and UI suite with:

```sh
xcodebuild test -project dev.xcodeproj -scheme dev -destination 'platform=macOS'
```

Automated checks cover Markdown rendering, API decoding, and timestamp formatting. The full-screen and narrow-window layouts should also be reviewed visually in the running app. A live GitHub account is needed to confirm the sidebar login against an actual session.

## Pull request review

Open and closed pull requests appear in the project Pull Requests page, which reloads the project PR list when opened so it catches PRs that arrived after the project overview was loaded. **Files & discussion** loads changed-file summaries and GitHub-provided patches, submitted reviews, inline review comments, and conversation comments. Large or binary files may not include a patch. Open pull requests allow a comment, a comment-only/approve/request-changes review, and a merge commit after confirmation. Closed requests remain inspectable. GitHub's Pull requests permission must be configured as **write** for these actions; GitHub branch protection and mergeability rules still apply. A 403 action error includes GitHub's response message when provided, to distinguish missing app permission from installation, repository, or organization access problems. Submitting a review refreshes the loaded contribution graph from GitHub; comments and merges remain PR activity rather than extra contribution counts.

Opening a pull request replaces the project view with a GitHub-style review page: title and status, base/head branches, merge status, Conversation/Commits/Checks/Files changed tabs with counts and diff totals, discussion content, and a metadata sidebar. Check runs load from the PR head commit; if GitHub withholds check data, the other PR detail sections still load and the Checks tab reports its own error. The header Code menu links to the PR on GitHub. **Merge…** opens an editable commit title and extended description before confirmation. A successful GitHub response updates the PR to **Merged** and refreshes the open count; GitHub's 405 and 409 merge responses explain merge requirements or a changed base branch, and 403 explains the required app permissions.

The Pull Requests page can create a PR by choosing a head and base from branches already pushed to GitHub, then entering a title and description. The Branches page also offers **Create pull request** for the selected non-default branch and preselects it as the PR head. Creating the PR adds it to the project PR list and updates the sidebar count. The app does not push a local branch. Project rows in the expanded and compact sidebar show the current open-PR count; counts refresh after repository discovery, project history loads, and PR creation.

## Typography and corners

App detail text uses a 12 pt minimum, including captions, badges, provider summaries, Skills, Quick Summary, terminal text, and chart labels. Font settings can enlarge text; Small never reduces it below 12 pt. The macOS system font and system monospace remain in use. App-drawn rounded cards, badges, borders, clips, and hit shapes use 8 pt corners. Icon sizes, decorative background glyphs, macOS-owned controls, and embedded websites keep their native styling.

Overview uses one 8 pt card each for Start, Recent projects, and Recent pull requests. Headings sit inside the cards; visible dividers separate headings and individual action/project/PR rows. Start actions remain fully clickable rows with their existing identifiers.

## Sheet dismissal

Clicking the workspace outside an app sheet closes it without activating the background control. This applies to New/Clone project, recent project/PR pickers, repository search, provider usage, file previews, project appearance, and PR creation. Inside clicks remain interactive. Nested sheets and app-modal file pickers protect the underlying form until dismissed. macOS confirmation dialogs keep their native behavior; dismissing a form does not submit it.
