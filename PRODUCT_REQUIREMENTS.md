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
- The project workspace uses a small set of clear destinations: **Overview**, **Branches**, **Commits**, **Pull Requests**, and **Issues**. Contributors and activity appear in context in the overview and activity views.
- Make the branch/commit graph the project’s main visual. Prefer source-linked branch, commit, PR, and status views over generic analytics charts. Keep remote GitHub state and local checkout state visibly labeled.
- Keep the hierarchy understandable when many repositories or branches exist: search/filter the project list; show branch and commit collections inside the selected project view rather than expanding every commit into the global sidebar.
- Replace All Projects landing content with a responsive welcome Overview. Start offers New project (create a named empty folder under a chosen parent), Open project (choose a local folder), and Clone project (choose an accessible GitHub repository and destination).
- Show recent local/GitHub projects and at least five recently updated PRs with project identity and PR state. Show More only when additional PRs are available; More opens the full recent-PR list. More on projects opens a searchable recent-project picker.
- Provide global, single-select animated background themes within workspace content areas; keep the app header unthemed. The default Pixel Mosaic fills the workspace with a large drifting pixel field inspired by the user reference; Terminal Stream renders a flowing ASCII luminance field, and Aurora Wave is one continuous pixelated wave rising from the bottom and cresting toward the top with subtle flowing glow and sparse sparkles. Respect Reduce Motion. Each theme has its own saved color choice from Aqua, Violet, Amber, and Emerald; Terminal Stream and Aurora Wave colors adapt to their selected palettes. The Overview right panel configures themes and no longer displays a commits heatmap.
- Add a header **+** that opens a right-docked tool panel with an embedded browser, an interactive local terminal, a Codex launcher that starts the installed `codex` CLI in the selected project folder, a new-tab launcher, and the three most recently opened local or cloned projects. The Codex launcher uses the Codex logo. The main workspace resizes beside the panel without overlap. Selecting a project changes the main workspace and leaves the panel open. Tool tabs can be opened and closed independently; closing the last tab closes the panel. Full-screen expands the selected tool to the app content area.

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

### GitHub project details

- **Pull requests:** list open and closed PRs; show title, author, reviewers, labels, checks/statuses, changed files and available patches, description, reviews, inline review comments, conversation comments, state, and merge time. Create a PR from branches already pushed to GitHub. On open PRs, allow a comment, a comment-only/approve/request-changes review, or a merge after confirmation. Show each project’s open PR count in the sidebar.
- **Issues and bugs:** title, state, author, assignee, labels, recent activity, and GitHub link.
- **Contributors:** contributor and PR-author identities, contribution context, and GitHub profile links. Avoid implying an exact ranking when GitHub data is incomplete.
- **Recent items:** a cross-project activity feed for new/updated PRs, commits, issue changes, reviews, and merges, with project/type/state filters.
- **Previews:** show links reported by GitHub checks or deployment statuses; open a selected link in the system browser. The app does not build or host a preview. A separate user-launched Browser tool can navigate ordinary HTTP(S) pages inside a tab, without a native JavaScript bridge.

### Generative AI and visualization

- Present a visual project pulse with branch/PR activity, pending reviews, recent merges, open issue counts, checks, and recent contributors.
- The graph and counts are derived from fetched GitHub records and local Git metadata, not invented by a model.
- When an AI provider is chosen and enabled, generate concise explanations/highlights and questions answered from the selected project’s fetched metadata and activity. Provide clickable source records for each claim.
- Do not read local source files for AI in v1. Do not send private repository data to an external model until a provider, data handling, and explicit user consent are defined.
- AI provider/model is deliberately undecided in this brief and is an implementation/release gate.

### Detection and notifications

- On launch/foreground, refresh compact PR summaries across all accessible repositories by default and report newly discovered or changed PRs. Fetch full PR conversations and changed-file lists when the user opens a PR.
- While the app is running, poll GitHub at a configurable interval and show in-app activity. Ask for macOS notification permission before sending system notifications.
- Pause polling when the app is quit or offline; show last successful refresh and a retry action. No webhook server is part of v1.

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

## Out of scope for v1

- Editing GitHub issues or PRs, labels, branches, releases, or repository settings; closing PRs; resolving review threads; or running GitHub Actions.
- Pushing commits or changing repository settings.
- Editing source files in the app. Local text-file previews are read-only and are limited to 2 MB per file. The explicit user-launched Terminal tool is an approved exception and has normal macOS account permissions.
- Creating additional Git worktrees or managing source changes. The app reports existing worktrees it can detect.
- Building/hosting previews. The explicit Browser tool may embed ordinary user-requested HTTP(S) pages but has no native bridge into app data or actions.
- Webhook infrastructure, team administration, shared dashboards, and organization analytics.
- AI code review or reading local/private source files for model prompts.
- Automatically cloning every accessible repository or deleting local clones.

## Decisions still needed before implementation

- Register and configure the GitHub App, exact permissions, repository installation scope, and organization approval path.
- Select an AI provider/model, data residency/retention requirements, consent language, and cost/latency target.
- Set the default polling interval and notification preferences.
- Decide whether manual linking of pre-existing local clones is needed later.
