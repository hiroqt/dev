# Password Manager verification — November 1, 2026

## Fix

The app previously built unsigned, then signed with an application identifier alone. The running app still failed native Keychain access with `errSecMissingEntitlement` (-34018). Build/signature success was insufficient evidence.

Enabled app-target signing and connected `Config/dev.entitlements` to Debug/Release. The final fix adds one private `keychain-access-groups` entry using `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`. Building with automatic provisioning embeds the development profile required to authorize that group. No vault authentication, encryption or storage policy was weakened; no authentication test bypass was added.

## Reproducible build/signing evidence

```sh
xcodebuild build -quiet -project dev.xcodeproj -scheme dev -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates
```

Passed. Build log: `/tmp/dev-vault-provision-build.log`. Debug app tested: `/Users/arnel/Library/Developer/Xcode/DerivedData/dev-cixveitmylvnfgevkvvkvvowxywb/Build/Products/Debug/dev.app`. Release configuration is wired but was not built.

`codesign --verify --deep --strict` passed. Entitlements and embedded profile were parsed and asserted:

- Signed app ID: `GVFU34LJU5.com.arnel.dev`.
- Exactly one private Keychain group: `GVFU34LJU5.com.arnel.dev`.
- Embedded profile authorizes the same app ID and the group via `GVFU34LJU5.*`.
- Profile expiry: **November 8, 2026, 10:21 PM Asia/Manila**. Xcode must renew/rebuild for subsequent development use.

A signed, non-mutating `SecItemCopyMatching` probe used a unique nonexistent service. Before provisioning it returned **-34018**; after provisioning it returned the expected **-25300 / errSecItemNotFound** (exit0). This checks real OS authorization rather than only inspecting the signature. Probe source: `/tmp/dev-vault-runtime-probe.swift`; its task-local signed executable/profile were removed after verification. No probe Keychain writes or deletions occurred.

## Real app E2E (CUA, with user-entered native authentication)

No real service credentials were used. Test data: service `E2E Test (disposable)`, username `vault-e2e@example.invalid`, later edited to `vault-e2e-edited@example.invalid`; password was a public synthetic fixture. The disposable record was removed during the later user-confirmed Delete test below.

| Check | Observed evidence | Result |
|---|---|---|
| Fresh native unlock | User completed the macOS prompt; CUA observed Add Login, Lock and empty vault, with no entitlement error | PASS |
| Add/save | Actual editor → Save; one card appeared, password masked | PASS |
| Reveal/hide | Reveal showed the synthetic value; Hide restored Hidden password | PASS |
| Edit/save | Edited username/password persisted in the same single card | PASS |
| Search | Unmatched query removed the card; edited username query restored it | PASS |
| Copy | Copy then normal keyboard Paste into search produced the exact edited fixture | PASS |
| Clipboard expiry | After more than30 seconds, empty search + normal Paste inserted nothing | PASS |
| Manual Lock | Login controls/details disappeared and Unlock button returned | PASS |
| Full quit/relaunch | Quit app, relaunch exact signed path: vault starts locked | PASS |
| Persistence | User authenticated after relaunch; edited username was present and Reveal matched the edited synthetic password | PASS |
| Navigation lock | Left unlocked vault for All Projects and returned: locked page, no login details | PASS |
| Cancel native authentication | From locked vault, requested native unlock; user clicked Cancel and left app untouched; CUA observed “Unlock cancelled. Your vault remains locked.” plus enabled Unlock button, no login details | PASS |

CUA accessibility observations are direct runtime checks; no fake store or authentication shortcut was used for this flow.

## Automated checks and limits

Baseline `/tmp/dev-vault-e2e-baseline.xcresult` passed four `PasswordManagerTests` (fake storage), but XCTest UI runner failed initialization with “Timed out while enabling automation mode.” This is not an automated E2E pass; direct CUA checks above supplied the native UI verification. DocSec unit tests passed3/3. `plutil -lint Config/dev.entitlements`, independent profile/entitlement assertion, independent read-only review and `git diff --check` passed.

Physical screen-lock/sleep, wrong-password attempts, multiple concurrent app processes, focus switching and Release runtime were not tested. No broad app E2E completion is claimed. No Google Authenticator/MPIN changes were made; those remain a separate product decision.

## Delete confirmation follow-up — November 1, 2026

Added native destructive confirmation naming the username/service. Cancel performs no write; confirmation removes only the selected UUID after a successful Keychain save. Failed writes leave the previous snapshot intact. Pending confirmation clears on lock. A session-scoped deleted-ID guard prevents stale edit sheets in another window from recreating deleted entries.

Focused `xcodebuild test ... -only-testing:devTests/PasswordManagerTests` passed **6/6** in `/tmp/dev-vault-delete-final.xcresult`. New tests verify selected-record persistence, unrelated-record retention, locked deletion refusal, failed-delete data preservation, and stale-edit rejection. Direct CUA testing passed: Delete opened a native alert naming the exact service/username; Cancel preserved the card. On a second attempt the user clicked the destructive Delete button; the card disappeared and the app showed “No saved logins.” No real credentials were deleted. Delete-after-relaunch was not separately tested. Independent final review found no further issues.

### Password Manager icon actions — 2026-11-01
Replaced per-login text actions with right-aligned footer icons ordered Reveal/Hide, Copy, Edit, Delete. Password content stays above the action row to avoid competing for width. Native SF Symbols use28pt label targets, tooltips and explicit accessibility labels; Delete stays red/destructive and retains confirmation. Only App/PasswordManager.swift UI changed; auth/persistence behavior unchanged. Native arm64 xcodebuild build passed (`/tmp/dev-vault-icons-build.log`), diff check passed. Existing six vault tests were not rerun for this cosmetic change; live unlocked-card visual QA not performed. No install/commit/push.
