# dev — Product Requirements Document

**Status:** Product brief for v1 design  
**Platform:** Native macOS app, written in Swift with SwiftUI  
**Primary user:** One person monitoring their own GitHub projects  
**Source of truth:** GitHub remains authoritative for remote repository, pull request, issue, and review data.

## Problem

The user manages multiple GitHub repositories and currently has to open each repository and local checkout separately to understand branches, commits, pull requests, contributors, issues, and recent changes. They want one polished macOS workspace that shows what is happening across projects and lets them inspect a selected project’s GitHub activity and local branch state.

## Product outcome

After signing in to GitHub, the user can discover repositories they are permitted to access, choose repositories to clone locally, and review a visual, source-linked summary of project activity. The app can read GitHub and inspect its own local clones. It does not modify GitHub or act as a code editor.

## Product principles

- **One personal command center:** cross-project activity is visible without losing repository context.
- **Visual first, verifiable:** graphs and status cards expose the underlying PR, commit, issue, or check when clicked.
- **Local state is explicit:** distinguish remote GitHub state from local clone and worktree state.
- **Read-only on GitHub:** v1 never creates, edits, merges, closes, or comments on GitHub resources.
- **AI is optional and grounded:** AI explanations cite the records they summarize; the app’s activity graph is computed from GitHub/Git data.

## Navigation and visual direction

- Use a familiar native macOS workspace shell: a persistent, collapsible sidebar beside a focused content area. Borrow the clear hierarchy and compact navigation pattern from Codex, while using `dev`’s own name, icons, colors, and GitHub-specific content.
- The sidebar has **All Projects**, **Activity**, a **Projects** section listing one item per GitHub repository, and **Settings**. Selecting a project opens that repository’s workspace. Do not create a separate folder layer in v1.
- The project workspace uses a small set of clear destinations: **Overview**, **Branches**, **Commits**, **Pull Requests**, and **Issues**. Contributors and activity appear in context in the overview and activity views.
- Make the branch/commit graph the project’s main visual. Prefer source-linked branch, commit, PR, and status views over generic analytics charts. Keep remote GitHub state and local checkout state visibly labeled.
- Keep the hierarchy understandable when many repositories or branches exist: search/filter the project list; show branch and commit collections inside the selected project view rather than expanding every commit into the global sidebar.

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

### GitHub project details

- **Pull requests:** title, author, reviewers, labels, checks/statuses, changed-file list, description/summary, conversation messages and comments, state, and merge time.
- **Issues and bugs:** title, state, author, assignee, labels, recent activity, and GitHub link.
- **Contributors:** contributor and PR-author identities, contribution context, and GitHub profile links. Avoid implying an exact ranking when GitHub data is incomplete.
- **Recent items:** a cross-project activity feed for new/updated PRs, commits, issue changes, reviews, and merges, with project/type/state filters.
- **Previews:** show links reported by GitHub checks or deployment statuses; open a selected link in the system browser. The app does not build, host, or embed a preview.

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
20. As the user, I want read-only behavior on GitHub so that the app cannot change my repositories or conversations.

## Acceptance criteria

- A first-run user can authorize GitHub and see accessible personal and organization repositories; permission and installation gaps are explained with a recovery path.
- The repository list is paginated and does not claim to show a repository that GitHub has not exposed to the authorized app.
- The user can choose a parent folder and clone a selected repository under its repository name. Existing/non-empty target paths are protected from overwrite.
- The project view distinguishes GitHub remote branches/commits from local branches, working-tree state, and linked worktrees.
- The branch graph can navigate to the related commit and, where available, PR/merge record. Deleted remote branches remain visible as historical PR/merge records when GitHub still exposes that data.
- PR detail includes all fields listed in the scope, with links to the authoritative GitHub page.
- Issues, contributor identities, and recent items show loading, empty, stale, and access-error states distinctly.
- Preview links require a user click and open only recognized web URLs in the system browser.
- New/changed PR detection covers all accessible repositories by default, runs on foreground and the configured polling schedule while the app is running, and shows per-repository stale state and rate-limit delays. Full PR details load on demand.
- No v1 action writes to GitHub. Clone/fetch are read operations against GitHub; local cloning writes only under the user-selected destination.
- Any enabled AI explanation identifies its source records. AI is unavailable until its provider/data-handling choice and consent flow are defined.
- The navigation consistently presents repositories as projects, with distinct cross-project **All Projects** and **Activity** destinations and project-specific **Overview**, **Branches**, **Commits**, **Pull Requests**, and **Issues** destinations.
- The interface targets the latest macOS release supported at implementation and remains usable with keyboard navigation, VoiceOver labels, and system appearance settings.

## Out of scope for v1

- Creating or editing GitHub issues, comments, PRs, labels, branches, releases, or repository settings.
- Merging PRs, pushing commits, resolving reviews, or running GitHub Actions.
- Editing, browsing, or executing source code in the app.
- Creating additional Git worktrees or managing source changes. The app reports existing worktrees it can detect.
- Building/hosting previews or embedding arbitrary preview pages.
- Webhook infrastructure, team administration, shared dashboards, and organization analytics.
- AI code review or reading local/private source files for model prompts.
- Automatically cloning every accessible repository or deleting local clones.

## Decisions still needed before implementation

- Register and configure the GitHub App, exact permissions, repository installation scope, and organization approval path.
- Select an AI provider/model, data residency/retention requirements, consent language, and cost/latency target.
- Set the default polling interval and notification preferences.
- Decide whether manual linking of pre-existing local clones is needed later.
