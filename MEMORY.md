# AI Quota Tracker (ClaudeBar) — Local Project Memory

**Last Updated:** 2026-10-29  
**Status:** Authorized Rule 2 Maintenance (Native Xcode Modernization & Antigravity IPC Staged)

## Architecture Invariants

- **Native macOS Menu Bar Footprint**:
  - Compact menu bar item displaying real-time AI quota, rate limits, and token burn across active frontier models.
- **Native Modernization Blueprint (2026-10-28 / Lens B Rank 2, Score: 8.76/10)**:
  - Authorized under Closure Mode Rule 2 (In-slot canonical maintenance).
  - **Keychain Security Migration**: Migrate provider API keys (Anthropic, OpenAI, OpenRouter) from plaintext JSON files (`~/.config/claudebar/config.json`) and User Defaults into native macOS Keychain via `Security.framework`.
  - **Background Daemon Modernization (`SMAppService`)**: Replace legacy launchd polling plists with macOS `SMAppService` XPC helper daemon for robust, non-blocking quota fetching.
  - **Local Antigravity Desktop IPC Probe**: Integration with local Antigravity desktop `language_server` via ConnectRPC (`exa.language_server_pb.LanguageServerService/GetUserStatus` and `GetConfiguredModels`) to monitor local Gemini/Claude quotas and active conversation states directly from the menu bar.

## Resolved Bug Patterns

- **Ephemeral ConnectRPC Port Handshake Teardown**:
  - *Root Cause*: External HTTP clients sending cleartext HTTP requests to the HTTPS TLS port (`59230`) trigger immediate connection reset (`EOF`) or HTTP 400 (`Client sent HTTP request to HTTPS server`).
  - *Fix*: External callers must query the dynamic cleartext HTTP mirror port (`59231`) or configure URLSession with custom TLS trust evaluation (`serverTrust`) for loopback certificates.
- **SQLite Timestamp Epoch Division Corruption**:
  - *Root Cause*: Querying `~/.gemini/antigravity/conversation_summaries.db` with integer epoch division (`last_modified_time / 1000`) corrupts filtering because timestamps are stored as ISO-8601 text strings (e.g. `'2026-10-28 20:55:22.430963+00:00'`).
  - *Fix*: Query strings directly or format via SQLite `datetime(last_modified_time)`.

## Reusable Conventions

- **ConnectRPC Authentication Header**:
  - All calls to `LanguageServerService` require header `X-Codeium-Csrf-Token: <UUID>` extracted from `language_server --standalone` process flags.
- **Non-Preemptive Queueing (`CascadeRunState`)**:
  - Polling status or dispatching messages does not cancel or corrupt active agent tool execution; messages queue cleanly until the model achieves an idle step.
- **Closure Mode Rule 2 Compliance**:
  - In-slot security hardening (Keychain) and helper fixes are authorized without consuming new build slots.
