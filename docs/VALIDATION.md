# v0.7.0 validation

Local validation on 2026-09-11, Intel macOS 15 with Metal and a physical Touch Bar:

- Fixture-only self-test: passed, including incremental JSONL parsing, counter resets, incomplete lines, Claude request deduplication, parent relations, activity and token separation, and idle focus rules.
- Native UI smoke: passed, including Metal offscreen rendering, size and opacity, detail toggling, Touch Bar view creation, exact numeric entry and independent logo scaling.
- Eight hardware/provider UI combinations: passed (Touch Bar on/off × empty/Codex/Claude/both). Menu entries, Touch Bar construction and Claude settings matched availability.
- Empty startup and late Claude-only discovery: passed without restarting the process.
- Dual-source process probe: passed; duplicates did not add tokens, incomplete records waited, one unavailable source retained prior values while the other continued.
- Integration and global-total probes: passed, including 82 records with an 80-record viewport and older index changes.
- Real 60-second idle focus process probe: passed; selected the active main conversation rather than a child.
- Plugin manifest validation and tracked-file publication audit: passed.
- README captures use generated synthetic sessions, with visually inspected native rendering.

Process test logs remain in ignored local Outputs folders. They are not shipped as usage data. GitHub Actions runs build and fixture checks; it does not certify physical Touch Bar interaction or on-screen GPU behavior. Apple Silicon runtime behavior needs a native-machine validation report.
