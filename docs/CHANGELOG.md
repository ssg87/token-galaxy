# Changes

## 0.7.3 — 2026-09-17

Make new-token rotation more pronounced with a continuous increasing response to token energy. The 100 / 100,000 / 1,000,000-token regression cases must each exceed three times their previous token-only rotation and remain ordered by increment size. Idle and sustained-work rotation, event envelopes, particle counts, geometry, preferences and accounting remain unchanged. Regression checks also verify the surge returns to slow idle.

## 0.7.2 — 2026-09-17

Restore the original active rotation baseline while retaining 0.7.1's slower idle speed. Keep active rotation through reply, tool-result, planning and delegation gaps for both providers when recent local records still indicate working. Completion, interruption, waiting, stale records and read errors do not sustain acceleration. No token counts, geometry or appearance settings are changed.

Regression coverage exercises seven working phases for both providers across 20-second record gaps and checks return to idle for five stop/stale conditions. A native process probe checks an actual JSONL reply gap and subsequent completion without inventing tokens.

## 0.7.1 — 2026-09-17

Reduce the galaxy's idle rotation baseline from 0.045 to 0.01125 (75% slower). Keep observed work/token acceleration coefficients, geometry, particle counts, size controls and opacity unchanged. The active-conversation threshold retains its original margin above idle.

Validation: fixture self-tests passed. An isolated native process measured idle rate 0.01125 and accelerated to 0.3442 after 100 newly recorded tokens, with exactly 100 observed tokens. Installed locally on Intel macOS while retaining appearance preferences. This patch has no new prebuilt GitHub release; the Releases page still offers 0.7.0.
