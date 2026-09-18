# Changes

## 0.8.0 — 2026-09-18

Give the overview an independent multi-family layout instead of the orb's 14–18-node selection. Every currently read record is represented, with a larger root nebula, nearby descendants, real immediate-parent links and root task labels. Stable family order survives selection and refresh; outline selection is restored by task ID. The field uses half the overview height and adapts to viewport size. Missing parents and cycles are bounded safely.

Keep the floating orb, Touch Bar, counters, work/surge speeds and appearance controls unchanged. Overview families use their own activity rather than provider-wide Claude activity; unrelated roots no longer share the orb's clearing mask. Large GPU payloads use buffers beyond Metal's 4KB inline limit, and overview particle budgets scale separately. Coverage includes 33 roots/160 records, >4KB node/link payloads, narrow windows, dense families, cyclic ancestry, hit testing and selection after refresh.

## 0.7.5 — 2026-09-18

Make idle motion perceptible at different node sizes: use a display-only rate of 0.0225 for the lead and 0.06 for small satellites. The idle lift fades out as activity rises, preserving sustained-work and token-surge speeds, accounting and automatic-focus scores. Add per-visible-node phase/rate diagnostics and overview visibility/minimization flags to distinguish imperceptible motion from a hidden/paused window. Checks verify actual phase advancement, no fabricated activity and unchanged surge speed.

## 0.7.4 — 2026-09-18

Restore current working states when a new overview/renderer opens, without replaying historical tokens or events. Synchronize overview selection with the orb, verify overview pause/resume, and avoid resetting the Metal pause state during every data refresh. Give the overview a visibility-gated common-run-loop frame driver so reopening does not depend on MTKView restarting its automatic display link. Include overview frame/pause diagnostics in the local status snapshot.

Strengthen moving packets along recorded parent-child edges. Replies/results/completion return toward the parent; an observed parent dispatch can highlight its already active child relationships. These are relationship/activity cues, not an inferred transcript of messages. Independent tasks gain no fabricated edges. Existing geometry, star counts, size controls, idle/work speeds and token-surge strengths remain unchanged.

Coverage includes snapshot restoration, known-edge direction, no replay, completed-task idle, and a native overview check for progressing frames through refresh, deliberate pause/resume and close/reopen.

## 0.7.3 — 2026-09-17

Make new-token rotation more pronounced with a continuous increasing response to token energy. The 100 / 100,000 / 1,000,000-token regression cases must each exceed three times their previous token-only rotation and remain ordered by increment size. Idle and sustained-work rotation, event envelopes, particle counts, geometry, preferences and accounting remain unchanged. Regression checks also verify the surge returns to slow idle.

## 0.7.2 — 2026-09-17

Restore the original active rotation baseline while retaining 0.7.1's slower idle speed. Keep active rotation through reply, tool-result, planning and delegation gaps for both providers when recent local records still indicate working. Completion, interruption, waiting, stale records and read errors do not sustain acceleration. No token counts, geometry or appearance settings are changed.

Regression coverage exercises seven working phases for both providers across 20-second record gaps and checks return to idle for five stop/stale conditions. A native process probe checks an actual JSONL reply gap and subsequent completion without inventing tokens.

## 0.7.1 — 2026-09-17

Reduce the galaxy's idle rotation baseline from 0.045 to 0.01125 (75% slower). Keep observed work/token acceleration coefficients, geometry, particle counts, size controls and opacity unchanged. The active-conversation threshold retains its original margin above idle.

Validation: fixture self-tests passed. An isolated native process measured idle rate 0.01125 and accelerated to 0.3442 after 100 newly recorded tokens, with exactly 100 observed tokens. Installed locally on Intel macOS while retaining appearance preferences. This patch has no new prebuilt GitHub release; the Releases page still offers 0.7.0.
