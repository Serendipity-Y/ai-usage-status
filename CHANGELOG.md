# 更新记录 / Changelog

## 未发布 / Unreleased — 2026-11-28

### 中文

- 新安装可通过内置 CodexBar CLI 适配器读取 Antigravity 双环。Codex 与 Antigravity 按来源识别额度，迟到的旧报告保留较新的读数。Chrome 接收器对并发写入使用同一时间顺序。
- Codex 按窗口时长匹配 5 小时和每周额度，兼容省略时长的旧数据。缺失的百分比显示为 `--`。重复的平台记录优先保留有效余额，同一份 Chrome 快照只写入一次。
- 菜单栏现在显示 Antigravity 的 Gemini 剩余额度。双环和大字模式左侧为 5 小时（5H），右侧为每周（7D）。紧凑单环只显示每周额度。
- Codex 额度仍可在悬浮卡中查看。Codex 刷新失败时，Antigravity 图标继续独立更新。某个额度窗口缺失时，对应位置显示 `--`，额度耗尽时显示 `0`。
- 仅收到外部工具余额时，余额照常更新，双环以灰色保留上次有效额度，悬浮卡显示采集时间。Codex 命令行与 Mac 应用统一剩余百分比的取整方式。Chrome 聊天快照的时间若超前超过 10 秒，应用会尝试备用来源。

### English

- New installations can read Antigravity windows through the built-in CodexBar CLI adapter. Codex and Antigravity validate quota identities. Older reports preserve newer readings, including concurrent Chrome reports.
- Match Codex windows by duration, with positional fallback for older responses that omit it. Missing percentages display as `--`. Duplicate platform entries retain a reported balance, and repeated Chrome snapshots skip redundant writes.
- The menu bar now shows remaining Antigravity Gemini quota. Double Ring and Large Readout show the five-hour window (5H) on the left and the weekly window (7D) on the right. Compact Ring shows weekly quota only.
- Codex quota remains available in the hover card. The Antigravity badge continues updating if a Codex refresh fails. A missing window displays `--`, and an exhausted window displays `0`.
- When only external balances arrive, those balances update while the rings show the previous quota in gray and the card identifies the last reading. The CLI and Mac app round remaining Codex quota consistently. Chrome chat reports over ten seconds ahead of the local clock trigger the existing fallback.

## v0.3.0 — 2026-11-24

### 中文

- **2×2 四宫格悬浮弹窗布局**：左栏拆分为上下两张独立卡片——**左上 `Gemini`**（普通聊天 5 小时 / 每周剩余百分比与重置时间，与右上 `Codex` 顶底齐平）、**左下 `Antigravity`**（5 小时 / 每周 / Argon 每周，与右下 `其他工具` 顶底齐平）。
- **Gemini 聊天额度 Chrome 扩展桥接**：新增 `integrations/gemini-chat/`（Chrome MV3 扩展 + Native Messaging 本机接收程序 `native_host.py` + 一键注册脚本 `install_native_host.py`）；登录 Chrome 里的 `gemini.google.com` 后即可每分钟后台静默同步 5 小时与每周额度到菜单栏，无需保持 Gemini Mac 设置页或网页标签打开；同时保留 macOS 辅助功能读取与本地快照作为兜底。
- **多数据源独立调度**：新增 `RefreshSchedule`，Codex、Antigravity/外部工具、Gemini 聊天各自独立刷新与退避重试，互不阻塞；当 Antigravity 某次未返回 Argon 桶时安全保留槽位不误报 0%。
- **测试覆盖**：新增 `GeminiChatQuotaTests`、`RefreshScheduleTests`、`gemini.test.mjs` 及 2×2 上下顺序布局断言测试（共 29 项 Swift 测试 + 8 项 Node 测试）。

### English

- **2×2 hover card grid**: Split the left column into two distinct cards—**top-left `Gemini`** (5-hour and weekly chat limits, height-matched with top-right `Codex`) and **bottom-left `Antigravity`** (5-hour, weekly, and Argon weekly, aligned with bottom-right external tool balances).
- **Gemini chat Chrome extension bridge**: Add `integrations/gemini-chat/` (Chrome MV3 extension + per-user Native Messaging host `native_host.py` + `install_native_host.py`). Syncs Gemini chat 5-hour and weekly limits in the background without keeping Gemini settings or web tabs open, with macOS Accessibility pane and cached snapshots as fallback.
- **Independent per-source refresh scheduling**: Add `RefreshSchedule` so Codex, Antigravity/external tools, and Gemini chat refresh and back off independently; preserve the Argon slot when temporarily omitted.
- **Tests**: Add `GeminiChatQuotaTests`, `RefreshScheduleTests`, `gemini.test.mjs`, and 2×2 layout order checks (29 Swift tests + 8 Node tests).

## v0.2.0 — 2026-11-23

### 中文

- **项目更名**：GitHub 仓库与文档展示名更新为 **AI Usage Status**（`Serendipity-Y/ai-usage-status`），本机应用包与配置目录保持 `CodexUsageStatus` 以兼容现有安装。
- **双栏悬浮弹窗布局**：重构悬浮卡片为左右双栏白底设计——左栏展示 Gemini / Antigravity 全部配额桶（最多 5 行，含进度条、百分比与重置时间），右栏依次展示 Codex（5 小时 / 每周进度条与可用重置次数）以及 WorkBuddy / Trae / Qoder / AgentRouter 剩余积分/余额与签到状态；全卡片采用表格式列对齐与左右等高齐平排版。
- **紧凑单环样式（Compact Ring 7D）**：新增 `30pt` 宽紧凑单环菜单栏图标，解决刘海屏右侧菜单栏空间紧张导致图标被遮挡的问题；支持在 `Display Style` 菜单中与双环 / 大字模式自由切换。
- **合规可扩展的外部额度适配器**：新增 Gemini 及外部工具（WorkBuddy / Trae / Qoder）并发独立刷新适配器，支持通过本地 JSON 快照文件（`GEMINI_QUOTA_FILE` 或默认 `~/Library/Application Support/CodexUsageStatus/gemini-quota.json`）或用户自定义可执行命令（`GEMINI_QUOTA_COMMAND` 或默认 `bin/fetch-gemini-quota.py`）接入；不内置任何未公开服务探测、Keychain 读取或 Cookie 抓取，且外部源异常不影响 Codex 主刷新。
- **多宿主联动启停（Lifecycle Helper）**：扩展 `QuotaLifecycle.swift` 与 `install.py` 支持多个 `--host-app`（默认自动检测本机已安装的 `ChatGPT.app`、`Gemini.app`、`Antigravity.app`）；三者任意一个运行即保持菜单栏显示，全部退出后自动关闭。
- **测试覆盖**：新增 `GeminiFetcherTests`、更新 `HoverLayoutTests` 以及 `test_lifecycle.py` 多宿主实机联动测试。

### English

- **Project rename**: Rename the GitHub repository and documentation to **AI Usage Status** (`Serendipity-Y/ai-usage-status`), while keeping `CodexUsageStatus.app` and its local support paths unchanged for compatibility.
- **Two-column hover card layout**: Redesign the popover into a balanced side-by-side white card—left column for Gemini / Antigravity quota buckets (up to 5 rows with progress bars, remaining percentages, and reset times), right column for Codex (5-hour / weekly progress bars and reset credits) plus WorkBuddy / Trae / Qoder credit balances and check-in status—with tabular column alignment and flush bottom edges.
- **Compact Ring (7D) display style**: Add a 30pt single-ring menu-bar style to avoid macOS notch overflow, switchable via `Display Style`.
- **Pluggable external quota adapter**: Add concurrent, isolated refresh support for Gemini and external tools via user-supplied local JSON files (`GEMINI_QUOTA_FILE` / default `gemini-quota.json`) or local executable commands (`GEMINI_QUOTA_COMMAND` / default `bin/fetch-gemini-quota.py`). Keeps the app strictly free of built-in credential/cookie/Keychain scraping.
- **Multi-host lifecycle helper**: Extend `QuotaLifecycle.swift` and `install.py` to accept repeatable `--host-app` arguments (defaulting to installed `ChatGPT.app`, `Gemini.app`, and `Antigravity.app`), keeping the badge alive while any configured host runs and quitting cleanly when all exit.
- **Test coverage**: Add `GeminiFetcherTests`, update `HoverLayoutTests`, and add multi-host coverage in `test_lifecycle.py`.

## v0.1.1 — 2026-10-28

本 Fork 的首个二进制发行版。既有的 `v0.1.0` 标签来自上游项目。

This is the first binary release of this fork. The existing `v0.1.0` tag belongs to the upstream project.

### 中文

- 改善额度刷新稳定性：等待 Codex app-server 初始化完成后再请求额度，并处理进程提前退出、输出阻塞和分段数据。
- 自动重试：首次失败后等待 60 秒，连续失败后依次等待 120 秒和 300 秒；成功后恢复正常刷新间隔。
- 改善失败提示：悬浮卡片保留上次成功的数据，并显示错误类型与上次成功时间；状态栏继续用问号表示当前数据未更新。
- 修复悬浮卡片在正常、失败和恢复状态间切换时，窗口高度不同步导致内容被裁切的问题。
- 增加本机诊断记录，仅记录固定错误类别、RPC 错误码和重试时间；不记录原始服务端输出、凭据或额度数值。
- 增加针对初始化延迟、错误输出阻塞、进程退出、超时、数据分段以及卡片尺寸切换的回归测试。

### English

- Improve refresh reliability by waiting for app-server initialization before requesting usage and handling early exits, blocked output, and split data.
- Retry failed refreshes after 60, 120, then 300 seconds; a successful refresh restores the normal interval.
- Keep the last successful snapshot in the hover card, with the failure category and last-success time. Question marks continue to indicate that the status-bar data is stale.
- Fix hover-card clipping when switching between normal, failed, and recovered states.
- Add local diagnostics containing fixed error categories, RPC error codes, and retry timing, without raw server output, credentials, or usage values.
- Add regression coverage for delayed initialization, blocked stderr, process exits, timeouts, split data, and popover resizing.

The macOS downloads are ad-hoc signed and have not been notarized by Apple; Gatekeeper may block them. See the release notes for details.
