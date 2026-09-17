# Changes

## 0.7.1 — 2026-09-17

Reduce the galaxy's idle rotation baseline from 0.045 to 0.01125 (75% slower). Keep observed work/token acceleration coefficients, geometry, particle counts, size controls and opacity unchanged. The active-conversation threshold retains its original margin above idle.

Validation: fixture self-tests passed. An isolated native process measured idle rate 0.01125 and accelerated to 0.3442 after 100 newly recorded tokens, with exactly 100 observed tokens. Installed locally on Intel macOS while retaining appearance preferences. This patch has no new prebuilt GitHub release; the Releases page still offers 0.7.0.
