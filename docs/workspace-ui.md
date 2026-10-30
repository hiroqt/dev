# Workspace UI behavior

The repository browser uses an adaptive SwiftUI grid with a 320-point minimum card width. It adds columns as the content area grows and lets cards fill the available width, including in fullscreen. Project workspaces scroll vertically so long commit messages and pull request descriptions remain readable.

Selecting a commit shows its complete message and GitHub link immediately below that commit. Each commit message and pull request description can be expanded or minimized independently. Each offers **Preview** (formatted Markdown) and **Markdown** (raw source) buttons; Preview is the default. Preview lays out headings, paragraphs, lists, quotes, and fenced code separately while preserving inline emphasis and links. Links open only after a click and only when they use HTTP or HTTPS. GitHub timestamps use `MMM d, yyyy, h:mm a` in the current time zone; missing or unreadable timestamps display “Date unavailable.”

Project navigation controls use consistent insets and a minimum height, and reflow into additional rows when the window is narrow.

The Overview card centers its heading, repository description, and history summary.

The sidebar shows the signed-in GitHub login. The app reads it from the authenticated, read-only GraphQL `viewer { login }` field. Sign out clears the displayed login with the local session state; no additional permission scope is needed.

## Verification

Run the macOS app and UI suite with:

```sh
xcodebuild test -project dev.xcodeproj -scheme dev -destination 'platform=macOS'
```

Automated checks cover Markdown rendering, API decoding, and timestamp formatting. The full-screen and narrow-window layouts should also be reviewed visually in the running app. A live GitHub account is needed to confirm the sidebar login against an actual session.

## Pull request review

Open and closed pull requests appear in the project Pull Requests page. **Files & discussion** loads changed-file summaries and GitHub-provided patches, submitted reviews, inline review comments, and conversation comments. Large or binary files may not include a patch. Open pull requests allow a comment, a comment-only/approve/request-changes review, and a merge commit after confirmation. Closed requests remain inspectable. GitHub's Pull requests permission must be configured as **write** for these actions; GitHub branch protection and mergeability rules still apply. Submitting a review refreshes the loaded contribution graph from GitHub; comments and merges remain PR activity rather than extra contribution counts.
