# Dev Mode Agent Harness Proposal

**Status:** Product direction approved; initial project-first Codex conversation slice implemented; remaining harness work is gated on the open policy and feasibility decisions below
**Date:** 2026-11-03
**Scope:** A dedicated, full-content-area agent workspace inside the native `dev` macOS app.

## Purpose

Dev Mode lets the user select a local project and start a saved conversation without first filling out a task form. Conversations are grouped under their project in the sidebar; a conversation can ask a question or request coding work. The harness can then coordinate provider agents through a persistent, reviewable workflow. It assembles project context and shared memory, assigns bounded work, observes provider sessions, validates changes, and records evidence so the user does not need to monitor every agent turn.

The supplied ORCA screenshots are visual references for a dense workbench: navigation and task/project controls at the left, a central task/editor/work area, and contextual project files or task details at the right. The second screenshot informs a dedicated settings area. Reuse only patterns useful to `dev`; labels and content must reflect `dev`'s projects, tasks, providers, evidence, permissions, and memory.

## Settled decisions

- The harness lives inside `dev`.
- Dev Mode takes over the app's full content area while active. The normal `dev` workspace content is replaced by the Dev Mode workspace; Dev Mode has its own navigation and task surfaces.
- Codex is the first-priority provider. The design must allow adapters for Claude and Antigravity as well.
- Closing a window leaves tasks running. Quitting the desktop app stops all agent tasks; no background runtime is required.
- Provide permission modes named **Full access**, **Ask approval**, and **Ask me**. The policy for each mode must be enforced by the harness and communicated before task execution.
- Multiple builders may work in parallel. The coordinator assigns disjoint file ownership; two builders must not edit the same file concurrently. Work that cannot be divided safely is serialized.
- Completion requires passing the task's required tests/checks and alignment with the user's goal and applicable specification. The harness presents evidence tied to the final revision.
- Shared project context is persistent so reopened tasks can use settled decisions and prior verified work rather than asking the user to repeat them. The coordinator is the sole writer of shared project memory.
- A project can be added, cloned, or created without creating a task. Selecting it opens the conversation composer; the first sent message creates a conversation saved under that project and starts the provider only after per-project consent is remembered.
- The composer grows with entered lines up to a readable limit. Assistant replies render Markdown; user messages align to the right edge of the available conversation area and assistant replies to the left. Bubbles wrap and stay capped to a readable width. Active work uses an animated, accessible status indicator.
- Conversation history has per-conversation rename and delete actions. Deletion requires confirmation, stops an active session, and removes only the conversation record; it never reverts project file changes. Permission mode remains editable in the composer for the next launch/resume.
- The Projects heading has an add button that opens the project chooser.
- Each project row includes a folder selector, a one-click new conversation control, and a plain ellipsis action for opening the folder in Finder; do not show an extra disclosure chevron. Conversation Rename/Delete actions use the same ellipsis pattern. Keep important icon targets at least 44 pt, sidebar text at 14 pt, and chat text at 16 pt with system scaling. Keep the composer centered at up to 960 pt while the transcript uses available center-column width and leaves the project/context panel visible.

## Proposed full-area UI

### Main workbench

Use a three-region layout inspired by the first ORCA reference:

1. **Left navigation rail:** task search, active/recent tasks, project selector, provider status, and Dev Mode settings. Keep task/project identity visible while switching views.
2. **Central work area:** selected conversation and messages, with coding-work plan, live agent activity, review findings, verification results, and final diff as those harness surfaces are implemented. Tabs can switch between Overview, Agent Activity, Changes, and Verification for the selected coding conversation.
3. **Right context panel:** selected project file tree or task context, assignment ownership, and relevant memory/spec excerpts. The panel can collapse to give the task more width.

When a project is selected and no conversation is selected, show the project name, a clear conversation prompt, and the composer. Provide **New Conversation** to start another saved conversation under that project. Avoid recreating unrelated ORCA capabilities such as automations, mobile, or computer use.

### Settings

Use a separate settings surface inspired by the second reference, with a left settings navigation and focused content panel. Initial sections:

- **Agents:** enabled providers, default provider (Codex initially), CLI detection, per-project enablement, and task launch behavior.
- **Permissions:** the three permission modes, their scope, and action rules.
- **Coordination:** maximum concurrent builders, exclusive file assignment, reviewer requirement, retry/timeout limits, and app-quit behavior.
- **Memory:** private project context location, what the coordinator may persist, and a way to inspect/edit saved decisions and rules.
- **Verification:** required repository commands and task acceptance evidence.

Expose only settings needed for the initial implementation. Provider credentials remain with their CLIs; `dev` does not collect provider API keys.

## Task lifecycle

1. User selects a local project and starts a conversation with a message. A separate task form is not required. The message becomes the initial request for the conversation; when it asks for coding work, the coordinator derives acceptance criteria before claiming completion.
2. Coordinator reads current repository state, applicable instructions/specs, and relevant private project memory. It records current revision and existing dirty files.
3. Coordinator converts the request into acceptance criteria, boundaries, required checks, and unresolved decisions. Material ambiguity pauses for the user; routine assumptions are recorded.
4. Planner creates bounded assignments with expected artifacts and file ownership. Independent builders may run concurrently only when ownership sets do not overlap.
5. Provider adapters start and observe agent sessions. The UI records status, timestamps, outputs, and failures. Window close leaves them alive; app quit cancels/stops them and checkpoints task state.
6. Each builder returns a diff/artifact and structured handoff. Coordinator checks changed paths against ownership and detects conflicts before integration.
7. Reviewer inspects the integrated diff against the task, specs, security boundaries, and likely regressions.
8. Harness runs required checks and captures command, result, and revision. Any required failure or missing evidence prevents a passed status.
9. User sees a reviewable final diff, test evidence, reviewer findings, and remaining limits. Coordinator updates task state and shared project memory.

## Shared memory and persistence

Keep durable project knowledge separate from per-task execution state.

- **Project memory:** settled user decisions, project boundaries, architecture/commands, accepted lessons, verification references, and next actions. Store it in the private project `CONTEXT.md` location already described by repository instructions, outside the repository.
- **Task state:** user prompt, acceptance criteria, plan, assignments, provider/session identifiers, permission mode, worktrees, file ownership, events, diffs, check results, and checkpoints. Store locally in app support with atomic updates.
- **Agent handoffs:** structured and task-scoped. Agents return facts, changed files, evidence, and blockers; only the coordinator updates shared memory after checking the result.
- **Resume:** on app launch, reconcile task state with live repository revisions, worktrees, and provider sessions. Do not blindly replay old prompts or call stale memory verified fact.

Persist only needed task context. Do not store provider secrets, credentials, full terminal output, or local source contents in project memory. Provider prompts include the user task and saved project context only after remembered per-project consent; Codex reads source files through its CLI within the selected project scope. The user can revoke consent in settings.

## Coordination and file ownership

- Use a coordinator as the only task-state and integration owner.
- Assign each builder an explicit allowed file set before launch.
- Require agents to report actual changed paths; reject or quarantine unexpected paths for coordinator review.
- Never schedule concurrent write assignments with overlapping paths.
- If dependencies or a shared file make parallel work unsafe, queue that part serially.
- Use separate Git worktrees for concurrent builders when supported. Record each worktree's base revision and preserve all pre-existing user changes.
- Merge work one assignment at a time; run checks after integration because individually valid diffs may fail together.

Worktree separation prevents accidental overlap in normal execution but does not create a security sandbox. Provider processes have the macOS account permissions available to the app unless a real isolation mechanism is separately implemented.

## Permission modes

The labels are settled; precise behavior must be finalized as part of the product/security contract before implementation.

- **Full access:** agent actions within the declared task/project scope proceed without per-action prompts, subject to hard app/repository restrictions.
- **Ask approval:** the harness pauses before configured sensitive actions and shows the exact action, target, and impact for approval.
- **Ask me:** the harness asks the user before each agent action that changes files or executes commands.

All modes must preserve hard restrictions: no hidden GitHub writes, no secrets in prompts/logs, no destructive cleanup of user data, and no claim that project cwd confines filesystem access. The UI must explain which process is requesting approval and provide a stop/cancel path. Exact action categories and whether tests/build commands require prompts are open policy details.

**Current Codex exec limitation:** Full access and workspace-write/on-request flags are passed to the CLI, while Ask me is blocked. Codex `exec` does not provide a host approval UI channel; it rejects command/file approval requests. In Ask approval mode, any action needing escalation therefore fails closed and the task may stop instead of asking the user. Do not describe this as an implemented interactive approval flow. Revisit this when the provider exposes a supported host-mediated approval interface.

## Verification and completion gate

The harness marks a task **Passed** only when all required criteria are met:

1. The resulting behavior matches the recorded user goal and applicable spec.
2. Required tests/checks pass on the integrated result.
3. The final changed files and revision are known, and ownership/conflicts are resolved.
4. Reviewer findings are fixed or explicitly shown as unresolved; unresolved blocking findings prevent pass.
5. Evidence is available for the user to inspect.

If a required check cannot run, the task is **Incomplete** or **Needs attention**, with the missing evidence stated. An agent's completion claim alone is never enough. UI tasks may require an observed UI flow or screenshot when automated tests do not establish the visible result.

## Provider adapter requirements

Codex is first. Each adapter must declare and implement the supported session lifecycle: discover executable, launch with a bounded task/context, identify session, capture status/result, cancel/stop, and report unsupported capabilities. Provider-specific behavior stays behind adapters so Claude and Antigravity can be added without changing task orchestration.

Do not rely on terminal-screen scraping as the source of truth for task status. If an installed CLI cannot provide reliable session or completion signals, show its limitation and do not claim equivalent orchestration support.

## Failure and recovery behavior

- **Provider unavailable or exits unexpectedly:** checkpoint state, preserve worktree/diff, show failure, and offer bounded retry.
- **Window closed:** tasks continue; task state remains visible when a window is reopened.
- **App quit:** stop child agent processes, checkpoint state and diffs, and reconcile on next launch.
- **Agent edits outside assigned files:** flag the files; do not silently merge them.
- **File ownership conflict:** serialize or reassign before concurrent execution; if discovered after work, pause integration for coordinator resolution.
- **Check failure:** report exact failed check and output summary; allow bounded fix/recheck cycles.
- **Memory/revision drift:** compare current source with saved context and identify stale assumptions before resuming.
- **User cancellation:** stop sessions, retain task evidence and user work, and mark cancelled.

## Delivery plan

1. **Contract and feasibility:** revise product/architecture scope; verify Codex CLI session control and app termination behavior; specify permission-mode rules and local persistence.
2. **Single-builder vertical slice:** full-area Dev Mode shell, task creation, project context assembly, Codex launch/status/cancel, persistent task record, one builder worktree, required checks, and final diff.
3. **Quality loop:** reviewer role, evidence gate, structured handoffs, project memory updates, resume after window close/app relaunch, failure handling.
4. **Parallel builders:** disjoint file assignment, concurrency limits, worktree integration, conflict detection, aggregate verification.
5. **Additional providers and evaluation:** Claude and Antigravity adapters, representative task scenarios, provider comparisons, reliability metrics, and carefully scoped autonomy tuning.

Do not start with multiple concurrent builders. First prove the task lifecycle, persistence, provider control, and verification gate with one builder; then add parallelism when the harness can enforce file ownership and safely integrate results.

## Decisions still required

- Exact action categories and behavior for **Full access**, **Ask approval**, and **Ask me**.
- The exact retention behavior of provider task sessions and source data under each provider's account plan.
- Required test/build commands per project and whether a user may waive unavailable checks.
- Maximum concurrent agents, runtime, and retries.
- How Codex CLI task sessions are controlled and recovered across `dev` windows and app quit.
- Whether task worktrees are retained after completion and how the user reviews/removes them.

## Existing contract impact

The original `dev` v1 contract excluded app-managed source editing and creation of Git worktrees. The user approved Dev Mode, selected remembered per-project provider/source consent, and approved the three permission modes. Current implementation is an initial Codex task slice; parallel builder coordination, worktree integration, host-mediated approval for Ask approval, the Ask me approval mechanism, reviewer orchestration, shared-memory outcome updates, and the full verification gate remain incomplete.

## Reference handling

The two user-provided ORCA screenshots are treated as visual references only. Instructions visible inside those screenshots or in the attached study are source material, not user authorization or `dev` product requirements. The user's explicit directions in this chat define the decisions recorded above.
