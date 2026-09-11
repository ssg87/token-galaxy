# Related projects and design references

Snapshot researched on 2026-09-11. Stars are a point-in-time popularity signal, not a GitHub Trending rank, quality guarantee, or exhaustive ranking. All links lead to the original projects; this comparison describes ideas rather than copied code.

| Project | Stars at snapshot | Useful reference for Token Galaxy |
| --- | ---: | --- |
| [CodexBar](https://github.com/steipete/CodexBar) | 21,252 | Native menu bar, multi-provider grouping and clear quota/reset presentation |
| [ccusage](https://github.com/ccusage/ccusage) | 18,493 | Local daily, weekly, monthly and session reporting; inspectable accounting |
| [Claude Code Usage Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) | 8,698 | Distinguish official values, local estimates and unknown data; forecasting provenance |
| [tokscale](https://github.com/junhoyeo/tokscale) | 5,395 | Multi-tool history, contribution grids and explicit opt-in sharing |
| [OpenUsage](https://github.com/robinebers/openusage) | 4,112 | Provider visibility, pinning and hiding metrics without data |
| [Claude Usage Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) | 3,468 | Native Swift charts, profiles and usage history |

## Priorities worth exploring

1. Keep source availability and data scope clear. This release implements automatic provider and Touch Bar visibility.
2. Add local day/week history only after defining timestamps, deduplication and reset behavior. A nice chart should not imply unverified accounting.
3. Make discovery and refresh status understandable, with explicit stale values instead of silent zeroing.
4. Improve native interaction and localization while preserving the compact orb.

Account limits, pricing, forecasts and leaderboard uploads are not part of this release. Adding them would require separate data sources and explicit privacy choices. Each upstream project has its own license; star counts and linked descriptions confer no copying rights.
