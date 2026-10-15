# 本地 Token 速度

Token Galaxy 0.10.1（build 39）提供正式应用菜单“查看 Token 速度…”、原生速度窗口和有限时长 JSON 采样，并支持正常记录继续计速、缺失记录单独提示。源码／本地安装支持这些入口，不代表已经发布 0.10.1 自动升级包；公开升级渠道仍以实际 Release 为准。

需要 macOS 15 或更新版本。基础入口支持 Token Galaxy 0.10.0；本页的部分统计行为需要 0.10.1（build 39）或更新版本。技能内的启动器不编译源码、不需要开发工具。以下示例从仓库根目录运行；安装技能后，将路径换为该技能目录内 `scripts/token_speed.sh` 的绝对路径。

```sh
plugins/token-galaxy/skills/token-speed/scripts/token_speed.sh show
```

启动器先查找 `~/Applications/Token Galaxy.app`，再查找 `/Applications/Token Galaxy.app`，并校验正式 bundle ID 和版本。可通过 `TOKEN_GALAXY_APP` 指定其他已安装路径。`show` 使用 `token-galaxy://speed` 打开现有应用中的速度窗口，复用正在运行的 GUI 进程；冷启动也支持该入口。窗口可切换 10、30、60 秒观测窗口，查看近 120 秒趋势，并按 Codex、Claude Code 或单个任务筛选。首次读取期间显示“正在读取本地记录…”，完成后建立基线；等待完整有效窗口后才显示数值。

技能位于 `plugins/token-galaxy/skills/token-speed/`，包含 `SKILL.md` 和自己的 `scripts/token_speed.sh`，整体安装后不依赖源码树或本页的相对路径。Codex 发现已安装技能后，可直接用 `$token-speed` 请求打开速度窗口、采样或演示。应用缺失或版本过旧时，启动器明确报错。

## 采样与演示

首次历史读取并建立基线后，再进行 15 秒观测，使用 10 秒窗口：

```sh
plugins/token-galaxy/skills/token-speed/scripts/token_speed.sh sample --seconds 15 --window 10 --provider all
```

`sample` 调用已安装应用的无窗口 JSON 命令，不启动第二个常驻 GUI 实例；标准输出只包含 JSON，可直接重定向保存结果。JSON 不包含真实对话标题、路径或正文。`--seconds` 接受 1–300，表示首次读取完成后的观测时长；首次读取历史需要额外时间，因此总耗时会更长。`--window` 接受 10、30、60，`--provider` 接受 `all`、`codex`、`claude`。未知或重复的选项会报错。如果观测时长短于窗口，结果可能仍在收集。`sampling.initialReadSeconds` 单列首次读取与建基线耗时，`observationSeconds` 表示基线后的实际观测时长，`elapsedSeconds` 保留总耗时，`durationSeconds` 是请求的观测秒数，`sampleCount` 包含基线采样。只观察某个任务时，需要同时明确来源：

```sh
plugins/token-galaxy/skills/token-speed/scripts/token_speed.sh sample --seconds 35 --window 30 --provider codex --task-id 'TASK_ID'
```

`TASK_ID` 是本地遥测中的任务标识；不要用对话标题代替。`all` 不能与 `--task-id` 合用，避免不同来源的同名标识被混为一个任务。

无私有日志的演示使用原生合成数据：

```sh
plugins/token-galaxy/skills/token-speed/scripts/token_speed.sh demo '/tmp/Token Speed Demo'
```

`demo` 输出原生状态截图，用于查看视觉效果。它不证明真实对话已被采样，也不代表真实速度。

## 数字表示什么

速度是“这台电脑上刚观测到的 Token 增量 ÷ 经过的单调时钟时间”。读取器以每秒两次的频率接收本地日志快照。统计只覆盖当前读取到的近期记录，每个来源最多 80 条；它不能完整代表所有历史会话。

| 显示状态 | 含义 |
| --- | --- |
| 收集中 | 刚建立基线，或尚未覆盖完整的有效窗口；速度还不能计算。 |
| 有效数字 | 已覆盖完整有效窗口的记录合计，单位为 tokens/s。 |
| 部分统计 | 正常记录继续计速；界面列出已统计、缺失或不可读、等待完整窗口的记录数量。 |
| 0 | 已完成有效观测窗口，该窗口没有新增 Token。 |
| 不可用 | 当前没有任何记录具备完整有效窗口；不按 0 处理。 |
| 重新收集 | 只为发生重置、失读或恢复的记录重建基线，正常记录继续计速；旧历史不补算成新活动。 |

例如当前 160 条记录中有 43 条日志缺失，另 117 条具备完整 10 秒窗口，窗口仍显示这 117 条的速度，并醒目提示“部分统计：已统计117/160条，缺失或不可读43条未计入”。恢复的记录先重新建立自己的完整窗口，期间正常记录不断流。一个来源全部不可用时，另一来源的有效记录仍继续统计并标记部分统计。

JSON `schemaVersion` 为 2。`coverage.includedRecordCount` 是本窗口纳入总速率的记录数，`excludedRecordCount` 是当前范围中未纳入的记录数；后者分为 `missingRecordCount`（缺失、不可读或数据不完整）和 `warmingRecordCount`（初始、重置或恢复后等待完整窗口）。`recordCount` 是该范围的当前记录数，`partial` 表示已有速度只覆盖部分记录或来源；`complete` 表示已纳入记录拥有完整的所选计速窗口，不等于所有记录都可用。趋势点也携带部分统计及纳入/排除数量。最近有效采样时间只取已纳入记录；未纳入记录不会让正常速度看起来陈旧。

三列“历史累计”仍展示当前观测范围的已知累计，可能包含未计速记录；界面在部分统计时明确提示这一差别。累计缺失不补零。输入或输出分类只要在任一已纳入记录中未知，该分类速度便保留未知，已知总速率继续显示。

输入 Token 已包含缓存部分。Codex 的 cached input，以及 Claude Code 的 cache read/cache write，都只作为输入的子集展示，不能再次加到输入或总量。累计 Token 与 tokens/s 是不同的量，不能把累计总数除以一个任选的短窗口来代表当前速度。

本地日志可能延迟或批量落盘。一次写入会形成尖峰，即使模型实际生成过程较平稳。这是日志观测速度，不能称为精确的模型生成 tokens/s，也不推断订阅剩余额度、计费金额或其他设备的使用情况。缺失、失败与间隙会排除对应记录，不冒充零值或完整覆盖。

## 开发预览

源码开发工具 `plugins/token-galaxy/scripts/token_speed.sh` 继续保留，提供 `show`、`sample`、`demo` 和 `build`，用于构建或复用源码对应的隔离预览。它与技能内调用已安装应用的脚本是不同入口。

预览产物位于 `plugins/token-galaxy/Outputs/TokenSpeedPreview/Token Galaxy.app`，bundle ID 为 `local.token-galaxy.speed-preview`，使用独立偏好域与状态目录。预览不注册 `token-galaxy` URL scheme，也不启动 Sparkle。开发启动器核对源码与成品指纹；首次源码构建可能下载固定并校验过的 Sparkle 依赖。

只构建、不打开窗口或读取会话：

```sh
plugins/token-galaxy/scripts/token_speed.sh build
```

开发入口支持 `--build` 强制重建，以及 `show`／`sample` 的 `--state-dir PATH`；编译失败或源码在编译期间变化时明确停止。技能内的正式应用入口没有构建命令。

`show` 只报告已请求打开窗口。实际原生窗口显示、真实日志观测与 Token 数值正确性，应分别核验。
