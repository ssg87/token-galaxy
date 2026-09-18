# Contributing

Build on macOS 15+ using `./build.sh`, then run the fixture self-test shown in README. Run the relevant process probes for reader changes. They use temporary synthetic data and require a logged-in desktop.

UI changes should also run the app's `--ui-smoke`, `--overview-check /tmp/galaxy-overview-check`, and `--capability-check /tmp/galaxy-capabilities.json` with both `CODEX_HOME` and `TOKEN_GALAXY_CLAUDE_HOME` pointing to temporary fixture directories. Verify empty, Codex-only, Claude-only and combined states with Touch Bar present/absent. Check real Metal rendering locally; CI self-tests alone do not validate GPU output.

Keep source reads read-only and preserve preferences. Do not commit Outputs, personal paths, session titles, screenshots of real conversations, databases, credentials or environment dumps. Explain behavior and validation in each pull request. Apple Silicon runtime reports are welcome.
