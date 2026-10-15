---
name: token-speed
description: Open the installed Token Galaxy speed window or sample local Codex and Claude Code observed tokens per second. Use for Token speed, token 速度, or throughput requests about locally recorded sessions. Requires macOS 15 and Token Galaxy 0.10.0 or later; does not measure exact model generation speed or account quota.
---

# Token speed

Use `scripts/token_speed.sh` inside this skill directory. Resolve it to an absolute path before executing it. The skill and script are self-contained and do not require the source repository or developer tools.

- For a visual speed monitor, run `token_speed.sh show`. It opens the native window with 10/30/60-second observation windows and a recent trend.
- For a bounded JSON observation, run `token_speed.sh sample --seconds 15 --window 10 --provider all`. A task filter requires an explicit provider, for example `--provider codex --task-id ID`. Sampling accepts 1–300 observation seconds after the initial historical read establishes a baseline; that first read adds extra time. A duration shorter than the window may only produce a collecting state.
- For a demonstration without private sessions, run `token_speed.sh demo OUTPUT_DIR`. It renders synthetic native states into the requested directory.

The launcher finds `~/Applications/Token Galaxy.app`, then `/Applications/Token Galaxy.app`. Set `TOKEN_GALAXY_APP` to select another installed app path. It verifies the formal bundle identity and requires version 0.10.0/build 38 or later. If the app is missing or outdated, report that result; the launcher does not build or substitute a preview.

`show` sends `token-galaxy://speed` to the installed app and reuses its running GUI process. `sample` invokes its headless JSON command before NSApplication initialization; stdout contains only JSON. These commands read session files without changing them. Report failures accurately, and distinguish a launch request from verified window visibility.

Describe the result as **locally observed token deltas per elapsed second**. The first snapshot is a baseline; historical totals do not become fresh activity. A full valid observation window is required for each included record. In Token Galaxy 0.10.1/build 39 or later, healthy records continue counting while missing, unreadable or warming records are excluded individually. A recovered record establishes its own new baseline and window without interrupting healthy records or replaying history. One unavailable provider does not block another healthy provider. Valid idle windows can be zero; no valid records means unavailable, never a fabricated zero. Input already includes cached tokens: cache is a subset, never an additional count. An unknown classification on an included record keeps that classification's speed unknown while known total speed remains usable. Batched or delayed log writes can cause spikes, so these figures are not exact model generation tokens per second, billing, subscription quota, or account-wide telemetry.

For schemaVersion 2, always report `coverage.partial` and included/excluded counts with a numeric rate. `includedRecordCount` counts records whose total-rate window is valid; `excludedRecordCount` separates `missingRecordCount` and `warmingRecordCount`. `complete` confirms the included records' selected window, not full source coverage. For example: “部分统计：已统计117/160条，缺失或不可读43条未计入”. Preserve this limitation in any summary or downstream chart. Trend points also identify partial coverage. Historical cumulative totals cover the current observed scope and may include excluded records; label them separately and explain “历史累计包含未计速记录” when partial. Never treat missing cumulative values as zero. Older schema/app versions do not have these partial-coverage semantics.

The readers inspect a bounded set of recent local records, at most 80 per provider, not every historical session. JSON omits conversation titles, paths and message bodies. Its sampling metadata separates `initialReadSeconds` and `observationSeconds`; `elapsedSeconds` retains total wall-clock elapsed time, `durationSeconds` is the requested observation duration, and `sampleCount` includes the baseline. A slow first read does not consume the requested observation time. The visual window shows “正在读取本地记录…” until the first sample arrives; a confirmed empty sample is a separate state.
