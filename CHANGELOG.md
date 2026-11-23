# 更新记录 / Changelog

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
