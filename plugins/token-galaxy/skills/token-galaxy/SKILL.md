---
name: token-galaxy
description: Open the native macOS Token Galaxy orb to visualize local Codex and Claude Code token usage, tasks and subagents. Touch Bar controls appear only on supported hardware. Requires macOS 15 or later.
---

# Token Galaxy

When asked to open Token Galaxy, run `../../scripts/open_native.sh` relative to this skill directory. It builds the bundled Swift source on first use with Apple Command Line Tools and opens the app. Compilation can take a few minutes. Report build errors accurately.

The application reads local Codex and Claude Code session files. It needs no API key or account connection. Do not request credentials. Do not edit session files or reset preferences when opening it.

Use the sparkles menu for task details, appearance, animation pause and quit. Missing sources and unsupported Touch Bar controls are hidden automatically. A blank installation shows a neutral empty state until sessions are discovered.

These are locally recorded token totals, not subscription limits, billable cost, or account-wide usage. The app can only report records available on this computer. Do not describe a process launch alone as verified rendering.
