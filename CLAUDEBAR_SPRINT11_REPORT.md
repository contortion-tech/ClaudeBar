# ClaudeBar Sprint 11 Report — Native Build & HOMEDEV Promotion (`MJ-019`)

**Date:** 2026-11-06
**Workspace:** `/Users/joakimthomter/Desktop/10_SYSTEMS/16_CLAUDEBAR`
**Branch:** `feat/zai-zcode-fallback-and-recap` @ `cb21ad2f` (tree clean before and after; no commits made)
**Task Authority:** `00__WEEKLY_TASKS/MEGA_JOBS.md` (MJ-019) · `04_PROJECTMONITOR/project-ideas.json` (`idea-claudebar-01`)

---

## 1. Result

| Gate | Result |
|---|---|
| Unit test suites | **4,094 tests — 4,094 passed, 0 failed, 0 skipped** (xcresult-authoritative; all 10 test bundles ran) |
| Release build | **BUILD SUCCEEDED** — `xcodebuild -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -configuration Release -derivedDataPath .build/derived clean build` (exit 0) |
| Ad-hoc signing | `codesign --force --deep --sign -` → `Signature=adhoc`, strict verify **OK** (staged and installed) |
| HOMEDEV install | `/Applications/HOMEDEV/ClaudeBar.app` (87 MB) — prior app backed up first |
| LaunchCodes | `floor` → `/Applications/HOMEDEV/ClaudeBar.app`; `launchcodes_verifier.py --json` **exit 0**, entry `ai-quota-tracker` PASS |
| Estate ladder | `verify-all.cjs` **12/12 PASS (exit 0)** |
| Tree isolation | `git status` clean (Tuist-generated `*.xcodeproj`/`*.xcworkspace` are gitignored by design) |

## 2. Test suite verification (Step 1)

- The brief's `-scheme Quotas` has **no test action** (Quotas is a framework scheme; 0 testables). Per the brief's fallback, the full suite was run instead via the repo's canonical command (`CONTRIBUTING.md`): `tuist test` — the workspace `ClaudeBar` scheme aggregates **all 10 test bundles** (AppTests, AcceptanceTests, DomainTests, InfrastructureTests, DataSourcesTests, AWSClientsTests, ProvidersTests, QuotasTests, DiagnosticsTests, LeaderboardTests).
- Authoritative counts from `xcrun xcresulttool get test-results summary` (Test-ClaudeBar-Workspace-2026.11.06_00-27-37): `result: Passed`, `totalTestCount: 4094`, `passedTests: 4094`, `failedTests: 0`, `skippedTests: 0`.
- Toolchain notes: Tuist is the repo's configured build system; `xcodebuild`/`tuist` require `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (system `xcode-select` points at CommandLineTools). Tuist cask upgraded 4.204.0 → **4.215.0** (CONTRIBUTING requires ≥ 4.209).

## 3. Environment repairs required before building (all non-source, gitignored)

The generated projects carried stale absolute paths from the repo's two previous homes (`…/777_AI_Quota_Tracker/…` in the legacy root `ClaudeBar.xcodeproj`, `…/16_AI_QUOTA_TRACKER/…` in the active `App/ClaudeBar.xcodeproj`), and the gitignored `Tuist/.build` dependency cache was absent in this checkout. Repair = the repo's own regeneration workflow:

1. `tuist install` — restored 35 source-control packages (incl. Sparkle 2.x artifacts).
2. `brew upgrade tuist` → 4.215.0.
3. `tuist generate` — regenerated `ClaudeBar.xcworkspace`, `ClaudeBarKit.xcodeproj`, `App/ClaudeBar.xcodeproj`, and 12 dependency projects with current paths (Sparkle now resolves to `16_CLAUDEBAR/Tuist/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework`).

Zero tracked files touched: `.gitignore` declares `*.xcodeproj` / `*.xcworkspace` ("Tuist generated (regenerate with: tuist generate)"). The legacy root `ClaudeBar.xcodeproj` (777-era path, referenced by no workspace) was left untouched.

## 4. Build, signing, installation (Steps 2–3)

- **Bundle:** `com.tddworks.claudebar`, version **1.0.0 (1)** — the repo's source `Info.plist` default; CI injects release versions from git tags, and a local dev-branch build carries none. Not fabricated.
- **Deliberate one-key deviation on the staged copy only:** `SUEnableAutomaticChecks → false`. The bundle embeds the upstream Sparkle feed (`https://tddworks.github.io/ClaudeBar/appcast.xml`); with version 1.0.0 installed, Sparkle would classify every future upstream 0.5.26+ release as a downgrade and silently never offer updates. Auto-check off removes that failure mode; manual checking still works. Source and repo untouched.
- **Ad-hoc deep sign** on the staged bundle → `Signature=adhoc`, `codesign --verify --deep --strict` OK.
- **Atomic install (canonical HOMEDEV pattern):** running instance detected (PID 68758) and left alive — `mv`-based swap:
  1. `mv /Applications/HOMEDEV/ClaudeBar.app → /Applications/HOMEDEV/.HOMEDEV_BACKUPS/ClaudeBar_v0.5.25_pre_sprint11.app` (0.5.25 build 241, 46 MB, intact — rollback = `mv` back).
  2. `ditto` staged bundle → `/Applications/HOMEDEV/ClaudeBar.app`.
  3. `codesign --verify --deep --strict` on installed copy → **OK**.
- The previously running 0.5.25 instance survives until relaunch; the new 1.0.0 build activates on next launch of `/Applications/HOMEDEV/ClaudeBar.app`.

## 5. LaunchCodes registration (Step 3c)

- `04_PROJECTMONITOR/01_LAUNCHER/launchcodes.json`, entry `ai-quota-tracker`:
  - `floor`: `"16_CLAUDEBAR"` → `"/Applications/HOMEDEV/ClaudeBar.app"`.
  - `summary` refreshed (buildability + install state + version/signing note).
  - `prod` terminal action already launches the installed app (`open /Applications/HOMEDEV/ClaudeBar.app`) — unchanged.
  - `verification.ranAt` re-stamped after a fresh verifier run.
- `python3 launchcodes_verifier.py --json launchcodes.json` → **exit 0**; `ai-quota-tracker`: `✅ [PASS] Folder exists`. (Verifier also reports pre-existing `[FAIL]` lines for long-retired entries — unrelated to this sprint; overall exit remains 0.)

## 6. Verification ladder (final)

| # | Gate | Command | Result |
|---|---|---|---|
| 1 | Bundle signature | `codesign --verify --deep --strict /Applications/HOMEDEV/ClaudeBar.app` | **OK** (exit 0) |
| 2 | LaunchCodes registry | `python3 launchcodes_verifier.py --json launchcodes.json` | **exit 0**, entry PASS |
| 3 | Estate ladder | `node 00__WEEKLY_TASKS/verify-all.cjs` | **12/12 PASS (exit 0)** |

## 7. Risks / notes for the owner

1. **Version semantics:** installed build is honestly `1.0.0 (1)` (local source default). Sparkle auto-check was disabled for the downgrade-masking reason above; if a CI-numbered version is preferred, the fix is a version-stamped CI build, not a hand-edited plist.
2. **Dev entitlements:** the ad-hoc build carries the repo's `Sources/App/entitlements.plist`, including `get-task-allow` (debuggable) and `disable-library-validation` — fine for HOMEDEV (local, non-quarantined), not a notarized release.
3. **Disk:** `Tuist/.build` cache is ~4.4 GB (gitignored); `tuist clean` reclaims it at the cost of re-fetching dependencies next build.
4. **Relaunch needed** for the running menubar instance to pick up the new bundle.
5. Legacy root `ClaudeBar.xcodeproj` still holds a dead 777-era absolute Sparkle path; harmless (not referenced by the workspace) but a candidate for deletion in a future housekeeping pass.
