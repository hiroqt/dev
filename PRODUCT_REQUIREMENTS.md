# dev — Product Requirements Document

**Status:** Product brief for v1 design  
**Platform:** Native macOS app, written in Swift with SwiftUI  
**Primary user:** One person monitoring their own GitHub projects  
**Source of truth:** GitHub remains authoritative for remote repository, pull request, issue, and review data.

## Problem

The user manages multiple GitHub repositories and currently has to open each repository and local checkout separately to understand branches, commits, pull requests, contributors, issues, and recent changes. They want one polished macOS workspace that shows what is happening across projects and lets them inspect a selected project’s GitHub activity and local branch state.

## Product outcome

After signing in to GitHub, the user can discover repositories they are permitted to access, choose repositories to clone locally, review a visual, source-linked summary of project activity, create pull requests from branches already pushed to GitHub, and complete selected pull-request actions. The app can read GitHub and inspect its own local clones. It does not push local branches. GitHub writes are limited to PR creation, comments, submitted reviews, and merges.

## Product principles

- **One personal command center:** cross-project activity is visible without losing repository context.
- **Visual first, verifiable:** graphs and status cards expose the underlying PR, commit, issue, or check when clicked.
- **Local state is explicit:** distinguish remote GitHub state from local clone and worktree state.
- **Limited PR actions:** v1 can create a PR from a branch already on GitHub, comment on and review PRs, and merge them. All other GitHub resources remain read-only.
- **AI is optional and grounded:** AI explanations cite the records they summarize; the app’s activity graph is computed from GitHub/Git data.

## Navigation and visual direction

- Use a familiar native macOS workspace shell: a persistent, collapsible sidebar beside a focused content area. Borrow the clear hierarchy and compact navigation pattern from Codex, while using `dev`’s own name, icons, colors, and GitHub-specific content.
- The sidebar has **All Projects**, **Activity**, a **Projects** section listing registered GitHub projects, a visually distinct **Local Projects** section for explicitly added folders, and **Settings**. Local and GitHub projects remain separate even when they refer to the same remote. Project rows can be pinned and reordered, and their context menu can open the folder in an installed coding IDE, reveal it in Finder, copy its path, or remove its dev sidebar entry. Removing an entry preserves the folder and never changes GitHub.
- Add a top-level **Skills** library for skills found in project clones, explicitly selected folders, and GitHub sources. Skills are searchable by name, purpose, and tags, grouped by editable purpose category, and have an offline preview with source and install-command details.
- The project workspace uses a small set of clear destinations: **Overview**, **Branches**, **Commits**, **Pull Requests**, and **Issues**. Contributors and activity appear in context in the overview and activity views.
- Make the branch/commit graph the project’s main visual. Prefer source-linked branch, commit, PR, and status views over generic analytics charts. Keep remote GitHub state and local checkout state visibly labeled.
- Keep the hierarchy understandable when many repositories or branches exist: search/filter the project list; show branch and commit collections inside the selected project view rather than expanding every commit into the global sidebar.
- Replace All Projects landing content with a responsive welcome Overview. Start offers New project (create a named empty folder under a chosen parent), Open project (choose a local folder), and Clone project (choose an accessible GitHub repository and destination).
- Show recent local/GitHub projects and at least five recently updated PRs with project identity and PR state. Show More only when additional PRs are available; More opens the full recent-PR list. More on projects opens a searchable recent-project picker.
- Provide global, single-select animated background themes within workspace content areas; keep the app header unthemed. The default Pixel Mosaic fills the workspace with a large drifting pixel field inspired by the user reference; Terminal Stream renders a flowing ASCII luminance field, and Aurora Wave is one continuous pixelated wave rising from the bottom and cresting toward the top with subtle flowing glow and sparse sparkles. Respect Reduce Motion. Each theme has its own saved color choice from Aqua, Violet, Amber, and Emerald; Terminal Stream and Aurora Wave colors adapt to their selected palettes. The Overview right panel configures themes and no longer displays a commits heatmap.
- Add a header **+** that opens a right-docked tool panel with an embedded browser, an interactive local terminal, a Codex launcher that starts the installed `codex` CLI in the selected project folder, a new-tab launcher, and the three most recently opened local or cloned projects. The Codex launcher uses the Codex logo. The main workspace resizes beside the panel without overlap. Selecting a project changes the main workspace and leaves the panel open. Tool tabs can be opened and closed independently; closing the last tab closes the panel. Full-screen expands the selected tool to the app content area.
- Add Codex, Antigravity, and Claude provider integrations to Settings and the selected project's tool launcher. Let users enable providers globally and per project, detect whether their CLI is installed, and launch the official CLI in a terminal tab rooted at that project. Show setup links when a CLI is missing; do not install provider software or collect provider API keys. Report account sign-in only when a documented local check supports it; otherwise show Unknown.
- Show a compact, expandable usage summary for Codex, Antigravity, and Claude in the workspace sidebar, compact-sidebar usage sheet, Quick Summary, and expanded notch panel. Show 5-hour, weekly, and credit values only when a provider exposes an official machine-readable source; mark unsupported values Unavailable and link to provider usage instructions. The user's plan label is descriptive only.
- Add a compact **Quick Summary** reachable from a notch-aware panel on notched Macs and a menu bar popover on every Mac. The collapsed panel aligns flush with the screen top and camera notch, expands downward when clicked, and minimizes from its header; the Settings toggle enables or disables the notch panel. Fit screen width and respect Reduce Motion. Show recent PR activity, total open PR count, Workspace/Skills/Terminal/Codex shortcuts, expandable provider usage rows, and a disabled Tasks row marked Coming soon. Animate new/updated PR and completed terminal command events in the panel. Keep event labels local and omit terminal output.

## V1 scope

### Sign-in and repository discovery

- Sign in with GitHub using a native desktop authorization flow.
- Support personal accounts and organizations where the user and app have access.
- List accessible repositories with owner, name, description, visibility, default branch, last-push time, and clone state.
- Filter/search projects and distinguish inaccessible or uninstalled organizations from an empty result.
- “All projects” means all repositories returned for the signed-in account and the app’s granted installation access. It does not bypass organization approval or repository policy.

### Local clones and Main Work

- Let the user choose a parent folder. Clone each selected repository into a child folder named after the GitHub repository.
- Do not clone every accessible repository automatically; cloning is an explicit per-repository or selected-repository action because repositories can be large.
- Show clone progress, outcome, local path, current branch, clean/modified state, ahead/behind status, last local commit, remote branch activity, and linked worktrees when discoverable.
- Show the default branch, available local and remote branches, commits per branch, and a navigable branch/commit graph.
- Refresh local remote-tracking information through read-only fetch. Never push.
- Do not overwrite a non-empty destination. Do not delete or replace a clone automatically.

### Local projects

- Let the user explicitly add any folder through the native folder picker; do not scan directories automatically.
- Store a security-scoped bookmark so access can be restored across launches. Removing a project removes only its app entry, never its folder.
- Give local projects a separate sidebar section and local-specific workspace with **Overview** and **Files**. The file view lists visible folder contents and allows folder navigation. Selecting a text file opens a bounded, read-only preview; Markdown uses the same Preview/Markdown/Expand controls as commit messages. Do not follow symlinks or show hidden files. Files cannot be edited. A user-launched terminal can execute commands with normal macOS account permissions; the selected project is its starting directory, not a filesystem restriction.
- A local folder and a GitHub repository are separate entries, including when the folder's Git remote matches that repository.

### Skills library

- Add a top-level Skills destination that can be used while offline. Each entry shows its name, description/purpose, tags, suggested/editable category, source, stored location, and any supported install command.
- After a clone or when the user refreshes a repository scan, find `SKILL.md` files and skill links advertised by Markdown documents. Show advertised links as candidates; import only when selected. The user can also choose a local skill folder or paste an npx/plugin install command that identifies a GitHub repository or marketplace.
- Search the saved catalog locally. Resolving a pasted command is user initiated and reads only GitHub source metadata/files. Do not crawl links recursively.
- Keep a local offline copy of imported skill folders and GitHub skills in Application Support. Copy regular files only, excluding hidden paths and symlinks; limit each import to 100 files, 2 MB per file, and 10 MB total. Retain an offline copy when its source disappears. Refresh replaces the stored source files and metadata while preserving user-edited categories.
- Offline preview renders UTF-8 text up to the existing 2 MB preview limit; other stored files remain listed but are marked unavailable for preview.
- Suggest categories deterministically from the skill's name, description, and tags. Let the user change the category. Skill content and install commands are untrusted data and are displayed as text.
- Show an install command only when the source documents it or when the source is GitHub and the known `skills` CLI command can be formed. Show provenance and a Copy action. Never run an install command.
- Accept supported Codex, Claude Code, Copilot CLI, Gemini CLI, and `npx skills add` command text. Parse its GitHub repository and optional skill/plugin selector, show matching files as candidates, and preserve the submitted command as inert copyable text. Never execute pasted commands.
- Do not transmit imported local skill files to AI or another provider. Online search sends the submitted query to GitHub. GitHub source access uses existing read access; do not add permissions or write operations for the library.

### GitHub project details

- **Pull requests:** list open and closed PRs; show title, author, reviewers, labels, checks/statuses, changed files and available patches, description, reviews, inline review comments, conversation comments, state, and merge time. Create a PR from branches already pushed to GitHub. On open PRs, allow a comment, a comment-only/approve/request-changes review, or a merge after confirmation. Show each project’s open PR count in the sidebar.
- **Issues and bugs:** title, state, author, assignee, labels, recent activity, and GitHub link.
- **Contributors:** contributor and PR-author identities, contribution context, and GitHub profile links. Avoid implying an exact ranking when GitHub data is incomplete.
- **Recent items:** a cross-project activity feed for new/updated PRs, commits, issue changes, reviews, and merges, with project/type/state filters.
- **Previews:** show links reported by GitHub checks or deployment statuses; open a selected link in the system browser. The app does not build or host a preview. A separate user-launched Browser tool can navigate ordinary HTTP(S) pages inside a tab, without a native JavaScript bridge.

### Coding provider integrations and usage

- Support Codex (`codex`), Google Antigravity (`agy`), and Claude Code (`claude`) as locally launched project tools. Enablement is separately configurable in Settings and per project. Each launch uses the selected project's folder as its initial terminal directory; it does not send prompts or files from dev.
- Detect installed CLI commands from the app's environment and common macOS CLI locations. If a command is missing, show the provider's setup link and do not install it.
- Use Codex's documented `codex login status` check only when the user asks to check sign-in. Show Connected only when that command succeeds; otherwise keep the state Unknown. Antigravity and Claude sign-in remain Unknown in dev and can be checked in their own CLI.
- Antigravity's official read-only `agy -p /usage --output-format json` and `agy -p /credits --output-format json` commands supply model quota and credit data. Codex's local `codex app-server --listen stdio://` JSON-RPC `account/rateLimits/read` response supplies its account plan, quota windows, and optional credit balance. Read both providers from the user's home directory, validate their structured responses, keep only the current snapshot in memory, and refresh on demand and every five minutes while enabled; refresh Codex after launching its CLI. Codex protocol compatibility may vary by CLI version; show Unavailable on missing or invalid responses. In the Codex project terminal, detect only a standalone `/status` or `/usage` keystroke sequence to trigger an immediate structured refresh; do not retain other typed input or inspect terminal output. Claude usage remains Unavailable in dev; link to its official usage instructions. Never scrape interactive terminal output or inspect credential stores.
- Show a provider-reported account plan when the usage response supplies it. Let users optionally select or enter an informational plan label; a user label never drives inferred limits, estimates, or reset times. Codex and Antigravity structured usage sources refresh on demand and every five minutes while enabled; Claude is not polled.

### Generative AI and visualization

- Present a visual project pulse with branch/PR activity, pending reviews, recent merges, open issue counts, checks, and recent contributors.
- The graph and counts are derived from fetched GitHub records and local Git metadata, not invented by a model.
- When an AI provider is chosen and enabled, generate concise explanations/highlights and questions answered from the selected project’s fetched metadata and activity. Provide clickable source records for each claim.
- Do not read local source files for AI in v1. Do not send private repository data to an external model until a provider, data handling, and explicit user consent are defined.
- AI provider/model is deliberately undecided in this brief and is an implementation/release gate.

### Detection and notifications

- On launch/foreground, refresh compact PR summaries across all accessible repositories by default and report newly discovered or changed PRs. Fetch full PR conversations and changed-file lists when the user opens a PR.
- While the app is running, poll GitHub every minute by default, configurable to five or fifteen minutes, and show in-app activity. Stagger repository requests and back off at least five minutes after partial/API failures or rate limits. System notifications are off by default and require an explicit Settings toggle followed by macOS permission; Quick Summary popups remain in-app.
- Pause polling when the app is quit or offline; show last successful refresh and a retry action. No webhook server is part of v1.

### Quick Summary

- Keep the summary brief: show total open PRs and up to three recent PR rows with source links, plus shortcuts to Workspace, Skills, Terminal, and Codex.
- On notched displays, show a compact black cap centered over the measured camera notch, with short status glances on each side and curved shoulders joining the screen top. Keep it flush with the display top, within the top safe area, and clamp its measured-notch-based width to the screen. Clicking the collapsed notch expands the summary downward with the selected workspace theme below a camera-safe strip. Two floating tool pills beneath the summary switch between the summary, searchable Skills preview, embedded Terminal, and Codex inside the notch. Shell sessions stay mounted when switching tools or collapsing the notch; only the explicit Open Workspace button foregrounds the full app. The minimize control returns it to the idle notch. Click-away and Escape collapse it. Respect Reduce Motion. On other displays, use the same content in a persistent menu bar entry.
- Animate new/updated PRs and completed interactive shell commands into the summary. PR change detection compares up to eight most recently updated PRs per repository before limiting the visible overview to eight total. Terminal hooks are scoped to the child shell, write no user shell configuration, retain only the executable label and exit state, and never retain command arguments or output. Optional macOS notifications include new/updated PRs and command completion only after the user enables them in Settings and grants OS permission.
- AI-generated insights and Tasks are disabled “Coming soon” rows; provider usage values are displayed only from supported provider sources and are not sent to an AI model.

### Monitoring

- Add Monitoring to both sidebar modes. The content area has Server / Deployment, Computer, and AI tabs; display only the selected tab’s content. Server / Deployment contains hosting connections and uptime; Computer contains Mac metrics/charts; AI contains subscription quotas and API reporting. Show live Mac CPU, RAM, swap, disk space and aggregate network throughput; retain minute samples for seven days locally. Monitoring runs while dev is running; sleep/closed intervals are gaps.
- Read Vercel/Render deployment state using explicitly connected accounts. Vercel discovers personal and accessible team projects with paginated reads and explicit partial/access warnings. An adaptive overview places an account snapshot and recent releases beside searchable, account-filtered project cards, six per page. Cards show provider-reported domains, newest release/source and status. Selecting a project replaces the overview with a dedicated page and All projects back navigation: current-production endpoint, domains, source/creation metadata, seven-day numeric browser analytics, Observability links and latest/previous deployment history. Current production comes only from Vercel’s returned production target; previews are not labeled production, unknown metrics stay unknown, and no website previews are fetched automatically. Selectable history rows expose details. History shows five deployments per visible page with Previous/Next, using cached history before fetching older pages. Loaded counts are distinguished from unknown remote totals; empty, loading and failed states remain visible. Render services use paginated cards. Connection settings remain expandable. Read instrumented browser Web Analytics when supported and label it separately from network traffic. Provide the project’s Vercel Observability dashboard for bandwidth, edge requests, errors, latency and other unsupported metrics; no private API scraping or ingestion service. Probe only user-added HTTPS uptime URLs, showing observed availability and response time, never claiming continuous external uptime.
- Reuse Codex/Antigravity quotas; label unavailable Claude subscription data. Separately report OpenAI and Anthropic organization API usage and costs over seven days with reporting credentials. Never infer spend from subscription quotas.
- Store connection secrets in Keychain. Keep metric/uptime history local; exclude prompts, source, response bodies and credentials. Show stale/error/partial states and page-only warnings; no monitoring notifications or deployment mutations.

## User stories

1. As the user, I want to sign in to GitHub so that the app can show repositories I can access.
2. As the user, I want to include personal repositories and organizations so that my project list reflects my full GitHub workspace.
3. As the user, I want to see which repositories the app can access and why some organizations may be missing.
4. As the user, I want to search and filter repositories so that I can focus on a project quickly.
5. As the user, I want to clone a selected repository to a folder I choose so that its branches and local status are available in the app.
6. As the user, I want clone progress and clear errors so that I know whether a local checkout is usable.
7. As the user, I want to see the default branch and local/remote branches so that I understand the repository’s current shape.
8. As the user, I want a branch graph with commits so that merges and parallel work are easy to follow.
9. As the user, I want to see local working-tree changes and ahead/behind state so that local status is not confused with GitHub status.
10. As the user, I want to inspect a branch’s commits so that I can trace what changed over time.
11. As the user, I want PR reviewers, labels, checks, changed files, discussion, and merge time together so that I can assess the full review path.
12. As the user, I want to see issues and bugs with their current status so that open work is visible beside code activity.
13. As the user, I want to see contributors and PR authors so that I can understand who is participating.
14. As the user, I want recent activity across projects so that I can spot changes without opening each project.
15. As the user, I want new or changed PRs surfaced while the app is running so that I can follow ongoing work.
16. As the user, I want check/deployment preview links so that I can open the result associated with a PR.
17. As the user, I want a visual project overview with source links so that I can understand activity and verify details.
18. As the user, I want AI explanations to use selected GitHub data and link to evidence so that summaries remain reviewable.
19. As the user, I want to control AI use and notifications so that the app’s data handling matches my preferences.
20. As the user, I want to create a PR from a pushed branch, inspect closed PR files and discussion, comment or submit a review on an open PR, and merge an open PR after confirmation.
21. As the user, I want to collect skills from cloned repositories, selected folders, and GitHub so that I can search and preview them offline by purpose.
22. As the user, I want to glance at PR activity and open counts from the notch or menu bar and jump to common tools without foregrounding the full workspace.
23. As the user, I want to enable Codex, Antigravity, and Claude globally and per project, launch each CLI from that project's folder, and see whether the CLI and a documented sign-in check are available.
24. As the user, I want provider plan labels and clear links to provider-reported 5-hour/weekly usage without dev guessing limits or reading provider credentials.

## Acceptance criteria

- A first-run user can authorize GitHub and see accessible personal and organization repositories; permission and installation gaps are explained with a recovery path.
- The repository list is paginated and does not claim to show a repository that GitHub has not exposed to the authorized app.
- The user can choose a parent folder and clone a selected repository under its repository name. Existing/non-empty target paths are protected from overwrite.
- The project view distinguishes GitHub remote branches/commits from local branches, working-tree state, and linked worktrees.
- The branch graph can navigate to the related commit and, where available, PR/merge record. Deleted remote branches remain visible as historical PR/merge records when GitHub still exposes that data.
- PR detail includes the fields listed in scope, changed-file patches when GitHub provides them, review history, inline review comments, and conversation comments, with links to the authoritative GitHub page. The user can create a PR using an existing remote head/base branch. Open PRs expose comment, review, and confirmed merge actions; closed PRs remain inspectable without write actions. The contribution graph keeps GitHub's contribution-calendar counts; comments and merges remain activity rather than invented contribution types.
- Issues, contributor identities, and recent items show loading, empty, stale, and access-error states distinctly.
- Preview links require a user click and open only recognized web URLs in the system browser.
- New/changed PR detection covers all accessible repositories by default, runs on foreground and the configured polling schedule while the app is running, and shows per-repository stale state and rate-limit delays. Full PR details load on demand.
- GitHub writes are limited to explicit PR creation, comments, reviews, and confirmed merges. Clone/fetch remain read operations; local cloning writes only under the user-selected destination. The app never pushes a local branch.
- Any enabled AI explanation identifies its source records. AI is unavailable until its provider/data-handling choice and consent flow are defined.
- The navigation consistently presents repositories as projects, with distinct cross-project **All Projects** and **Activity** destinations and project-specific **Overview**, **Branches**, **Commits**, **Pull Requests**, and **Issues** destinations. Project sidebar entries can be renamed and assigned a color and system icon for the sidebar, pinned, and drag-reordered; their settings/context menu can open the folder in an installed coding IDE, show its full path and reveal it in Finder, or remove only the dev entry while preserving local files and GitHub state. Sidebar labels, colors, and icons do not rename or modify the project itself.
- The interface targets the latest macOS release supported at implementation and remains usable with keyboard navigation, VoiceOver labels, and system appearance settings.
- Repository cards adapt their column count and content width to the available window size, including fullscreen; commit messages and PR descriptions appear with their own records and can be expanded or minimized, messages offer readable Preview and raw Markdown modes, timestamps use `MMM d, yyyy, h:mm a`, project navigation buttons have consistent padding, the sidebar identifies the signed-in GitHub username, and project rows show open PR counts.
- Users can add any folder explicitly to Local Projects; local folders have a separate visual identity and Overview/Files pages. The Files page navigates visible folders and opens text files in a bounded, read-only preview; Markdown files share the commit message Preview/Markdown controls. Hidden files and symlinks are not opened, and removing an entry does not delete its files.
- The welcome Overview provides New/Open/Clone actions, recent projects, at least five recent PRs and a full-list action when more are available, a searchable recent-project picker, and global selectable backgrounds with independently persisted per-theme Aqua, Violet, Amber, or Emerald colors that respect Reduce Motion.
- The header tool panel docks at the right and can be resized across the available width while preserving a usable workspace area. Its width adapts to window resizing and uses the full content area when side-by-side layout no longer fits. It provides an embedded HTTP(S) browser, interactive local terminal, Codex launcher using the installed CLI and Codex logo, recent project shortcuts, multiple retained tabs, last-tab close behavior, and full content-area preview.
- Settings lets users enable Codex, Antigravity, and Claude globally, label their provider plan, and check Codex sign-in on demand. Each selected project can enable or disable the installed CLI separately. The launcher starts each CLI in that project's folder and offers setup guidance if it is missing. Provider sign-in remains Unknown where no documented local check exists. The sidebar, compact-sidebar usage sheet, and Quick Summary show expandable per-provider usage; the expanded notch includes the same summary. Antigravity uses its official structured CLI usage/credits responses; Codex uses its local app-server rate-limit response and reports the plan when returned; Claude remains Unavailable in dev. User-entered plan labels do not infer limits.
- Quick Summary exposes recent PRs, open-PR total, Workspace/Skills/Terminal shortcuts, and the Codex shortcut when Codex is globally enabled (enabled by default) from the menu bar and notch-aware panel. The collapsed notch aligns with the camera housing and expands downward; its header, click-away, and Escape minimize it. Settings controls the notch panel, which adapts to screen width and Reduce Motion; screen changes refresh measurements. PR checks default to one minute, are configurable to five or fifteen minutes, and back off on API failures. Terminal completion labels are local and contain no output. macOS notifications are opt-in.
- The Skills page supports offline catalog search by name, purpose, and tags; category suggestions and user edits; automatic SKILL.md scans after cloning and on manual refresh; advertised GitHub links and user-selected folders; pasted Codex, Claude Code, Copilot CLI, Gemini CLI, and `npx skills add` commands; source and stored-location details; and offline copies that survive source loss. Copies exclude hidden paths and symlinks. Install commands are attributed, copyable, and never executed. UTF-8 preview is limited to 2 MB per file.
- The Skills page is searchable offline, resolves supported install commands into GitHub skill candidates on submit, scans clones after clone and manual refresh, shows advertised links as import candidates, supports manual folder import, suggests editable categories, and retains local offline copies when source access is lost. Hidden files and symlinks are excluded from copies. Install commands are attributed and copyable but never executed.
- Quick Summary works from a persistent menu bar popover and, when a display reports a physical notch, a top-anchored panel that expands on click and minimizes from its header. It fits narrow displays, collapses on click-away or Escape, refreshes display measurements, exposes recent PRs/counts and four shortcuts, shows expandable provider usage, and animates activity while respecting Reduce Motion. Tasks remain a disabled placeholder. Polling is configurable with a one-minute default and backs off on API failures. System notifications are optional and require explicit Settings and macOS permission.
- GitHub search and file reads are GET-only and use the existing public access or repository Contents read permission. No additional GitHub permission or repository mutation is introduced.

- Monitoring is available in both sidebar modes with native Mac metrics, seven-day local metric and observed-uptime history, read-only Vercel/Render deployments and separate OpenAI/Anthropic API reporting. Credentials stay in Keychain; unavailable, stale and partial data are labeled, and monitoring sends no macOS notifications.

## Out of scope for v1

- Editing GitHub issues or PRs, labels, branches, releases, or repository settings; closing PRs; resolving review threads; or running GitHub Actions.
- Pushing commits or changing repository settings.
- Editing source files in the app. Local text-file previews are read-only and are limited to 2 MB per file. The explicit user-launched Terminal tool is an approved exception and has normal macOS account permissions.
- Creating additional Git worktrees or managing source changes. The app reports existing worktrees it can detect.
- Building/hosting previews. The explicit Browser tool may embed ordinary user-requested HTTP(S) pages but has no native bridge into app data or actions.
- Webhook infrastructure, team administration, shared dashboards, and organization analytics.
- AI code review or reading local/private source files for model prompts.
- Cross-provider usage aggregation, estimating quotas/reset times from plan labels, or reading provider credential stores.
- Installing, updating, or syncing skills into agent tools. The library only catalogs and previews skills.
- Automatically cloning every accessible repository or deleting local clones.

## Password Manager — 2026-11-01

User-approved scope: a Mac-only password vault unlocked with the Mac account password; no Google Authenticator, phone, separate master password, cloud sync or recovery flow. Provide a locked sidebar destination, service presets (Google, Facebook, Apple and other common services), custom services, multiple accounts, search, add/edit, reveal/hide and copy. Never collect the Mac password in app UI. Use macOS password authentication enforced by Keychain access control. Lock on navigation away, app background, sleep, session resignation and screen lock; clear revealed values/editor state and app-owned clipboard content. Clipboard copies expire after 30 seconds if unchanged. Each saved login supports deletion after a native confirmation naming the service and username; Cancel preserves it and failed writes retain existing data. No autofill, imports or export in this slice. Loss of access to the Mac account/Keychain has no app recovery mechanism.

## Decisions still needed before implementation

- Register and configure the GitHub App, exact permissions, repository installation scope, and organization approval path.
- Select an AI provider/model, data residency/retention requirements, consent language, and cost/latency target.
- Set the default polling interval and notification preferences.
- Decide whether manual linking of pre-existing local clones is needed later.

### Monitoring project insights refinement — 2026-11-01

Within the selected deployment project, show its own website icon, a metadata-evidenced production checklist, available daily browser analytics, an Observability dashboard link for unsupported metrics and searchable/paginated deployment branches. Missing evidence stays unverified; deployment history does not establish live branch existence. Direct, bounded HTTPS homepage/icon reads are authorized solely for website logos; do not execute scripts, fetch screenshots or use a third-party favicon proxy.

### Computer inspection extension — 2026-11-01

Computer includes a local process activity table (CPU, resident memory, searchable names), reported battery charge/health information with unavailable states, and an explicit on-demand app storage scan. Scans are read-only and bounded; distinguish bundle sizes and reliably attributed user data from unclassified storage. Do not delete files, request expanded OS permissions or infer disk causes from process memory. Process commands/arguments, storage contents and battery data stay local and are not added to metric history.

User approved Inspect + quit apps. Offer confirmed graceful quit for regular GUI apps, revalidate process identity, exclude dev itself and system/background processes. Do not force kill processes or bypass unsaved-work prompts.
