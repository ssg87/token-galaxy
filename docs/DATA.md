# Local data and privacy

Token Galaxy performs local, read-only telemetry. The application contains no analytics uploader, HTTP client, credential lookup or account login. Plugin installation uses GitHub and source compilation uses Apple's local tools.

## Codex

The default location is `~/.codex`, overridden by `CODEX_HOME`. The current reader uses `state_5.sqlite` and its `threads` table. It selects the latest 80 records for rendering and reads their rollout JSONL files incrementally. The menu total uses all indexed thread totals, replacing the recent records with available log totals. Archived records and subagents can therefore contribute to the menu even when absent from the orb.

Codex cached input is a subset of input and is not added again. The reader prefers the recorded cumulative `total_tokens`; it does not sum cumulative snapshots. Local storage schemas are implementation details and may change; this release does not promise compatibility with future state database versions.

## Claude Code

The default root is `~/.claude`. `CLAUDE_CONFIG_DIR` changes it; `TOKEN_GALAXY_CLAUDE_HOME` is an explicit application override. The reader scans project JSONL records and subagent files. Usage is deduplicated by request/message identity across repeated content blocks and owner records.

Claude total = input + cache creation input + cache read input + output. These fields have different semantics from Codex cached input. Token totals are not currency and do not imply a pricing multiplier. The latest 80 Claude task records appear in the visualization; the provider total includes all parsed records.

## Observation and availability

First observation establishes a baseline. Decreases, truncation and resets do not create negative or fabricated positive bursts. Temporary read failures keep the last known values with a stale/error indication. A source never seen and with no files is hidden; a previously known source that becomes unreadable remains visible as an error.

The app polls local sources approximately every 0.5 seconds with incremental log reads. Larger histories can make initial Claude discovery slower. Activity is inferred from observed logs; it is not a guarantee that a remote model is currently running.

Touch Bar detection reads IOKit device metadata only. It does not open HID devices or intercept keystrokes. UI controls are omitted on other hardware. `TOKEN_GALAXY_TEST_TOUCH_BAR=0/1` is a test override.

## Stored output

Display choices are stored using macOS UserDefaults. Normal operation writes a local runtime status snapshot to `~/Library/Application Support/TokenGalaxy/status.json` approximately every 1.5 seconds. It includes task identifiers, counts, recent event metadata and rendering diagnostics; treat it as private. It is never uploaded. Explicit diagnostics such as `TOKEN_GALAXY_PROBE_DIR`, `--inspect-origin`, render/capture commands and process probes can write local data; do not publish their outputs from real sessions. The repository excludes generated Outputs and contains synthetic fixtures only.

This application is not a billing system, account quota monitor, or financial record. It cannot reconstruct deleted logs or usage from other computers.
