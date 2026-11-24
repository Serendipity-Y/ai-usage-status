# AI Usage Status

轻量级 macOS 原生菜单栏 AI 额度看板（原 `Codex Usage Status`），用于一目了然地查看 **Codex（GPT）**、**Gemini / Antigravity** 以及 **WorkBuddy / Trae / Qoder** 等本地工具的剩余额度、重置时间与签到状态。

> 本项目基于 [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status) 扩展，与 OpenAI、Google 及各第三方厂商无官方关联。为保持向后兼容，本机应用包与配置目录仍沿用 `CodexUsageStatus`。  
> 完整更新日志：[CHANGELOG.md](CHANGELOG.md) ｜ [English](#english)

![AI Usage Status 2×2 悬浮弹窗效果图](docs/assets/hover-card-v0.3.0.png)

*以上为使用虚构示例数据渲染的实机界面效果图，不含任何真实账号数据。*

---

## 核心特性（中文说明）

- **2×2 四宫格白底悬浮弹窗**：鼠标停留在菜单栏图标约 `0.2s` 自动展开：
  - **左上（Gemini）**：展示 Gemini 普通聊天的 `5 小时` 与 `每周` 剩余百分比进度条与重置时间，支持 **Chrome 扩展后台静默同步**（无需常开设置页或网页标签），并保留 macOS 辅助功能快照兜底；
  - **左下（Antigravity）**：展示 Antigravity 的 `5 小时`、`每周`、`Argon 每周` 剩余百分比与重置时间；
  - **右上（Codex）**：展示可用重置次数（`availableCount`）、`5 小时` 与 `每周` 剩余百分比进度条及重置时间（与左上 `Gemini` 等高齐平）；
  - **右下（其他工具）**：以三列对齐方式展示 **WorkBuddy / Trae / Qoder / AgentRouter** 剩余积分/美元余额与签到状态（与左下 `Antigravity` 等高齐平）；
  - **底部通栏**：展示下次后台自动刷新时间。
- **三种菜单栏图标样式**：点击菜单栏图标 → **Display Style** 可自由切换：
  - **Compact Ring (7D)**（`30pt` 宽紧凑单环，专为刘海屏右侧菜单栏优化，不易被遮挡）；
  - **Double Ring**（5H / 7D 双圆环）；
  - **Large Readout**（大字百分比读数）。
- **多宿主自动启停联动（可选）**：安装本地 `quota-lifecycle` 守护进程后，默认监听本机已安装的 `ChatGPT.app`、`Gemini.app`、`Antigravity.app`——**任意一个在运行即保持显示，三者全部退出后自动关闭**。
- **隐私与安全边界**（详见 [PRIVACY.md](PRIVACY.md) 与 [SECURITY.md](SECURITY.md)）：
  - Codex 数据仅通过官方本地 `codex app-server` 的 `account/rateLimits/read` 方法读取；
  - 应用本身不读取任何凭据文件、Keychain、浏览器 Cookie 或 OAuth Token，不修改官方应用包，也不上传任何遥测数据。

## 环境要求

- macOS 13 或更高版本
- 已安装 ChatGPT 桌面端（`/Applications/ChatGPT.app`）或独立版 Codex（`/Applications/Codex.app`）
- 从源码构建或安装联动助手需 Xcode Command Line Tools（Swift）、Node.js 20+ 与 Python 3

## 从源码构建与安装

```sh
git clone https://github.com/Serendipity-Y/ai-usage-status.git
cd ai-usage-status
npm run install:macos
```

常用开发与校验命令：

```sh
npm test
swift test --package-path macos/CodexUsageStatus
npm run build:macos
```

## 可选：多宿主自动启停联动（ChatGPT / Gemini / Antigravity）

安装后将在登录时后台运行轻量监听进程，只在指定应用运行时显示菜单栏圆环：

```sh
python3 lifecycle/install.py install
python3 lifecycle/install.py check
```

如需自定义监听应用路径（可重复传入 `--host-app`）：

```sh
python3 lifecycle/install.py install \
  --host-app "/Applications/ChatGPT.app" \
  --host-app "/Applications/Gemini.app" \
  --host-app "/Applications/Antigravity.app" \
  --quota-app "/Applications/CodexUsageStatus.app" \
  --codex-bin "/path/to/codex"
```

停用联动监听：`python3 lifecycle/install.py disable`。

## 可选：Gemini 聊天额度 Chrome 扩展桥接（免常开设置页）

1. 注册本机 Native Messaging 接收端：
   ```sh
   python3 integrations/gemini-chat/install_native_host.py
   ```
2. 在 Chrome 打开 `chrome://extensions`，启用右上角 **开发者模式**，点击 **加载已解压的扩展程序**，选择 `integrations/gemini-chat/extension` 目录；
3. 确保 Chrome 已登录 `https://gemini.google.com` 后，扩展会每分钟自动只将两个百分比和重置时间发送到本机菜单栏（不导出 Cookie 或聊天内容），可随时关闭 Gemini 设置页与网页标签。

## 可选：接入 Antigravity 与其他工具数据源

悬浮窗左栏（Gemini）与右栏下区（WorkBuddy / Trae / Qoder）支持通过用户自主配置的本地数据源并发独立刷新，解析优先级如下：

1. 环境变量 `GEMINI_QUOTA_COMMAND`（指向本机可执行脚本，stdout 输出 JSON）
2. 环境变量 `GEMINI_QUOTA_FILE`（指向本机 JSON 文件）
3. 默认本地快照文件：`~/Library/Application Support/CodexUsageStatus/gemini-quota.json`
4. 默认本地采集脚本：`~/Library/Application Support/CodexUsageStatus/bin/fetch-gemini-quota.py`

JSON 数据协议示例：

```json
{
  "plan": "Antigravity",
  "buckets": [
    { "id": "gemini-5h", "label": "5 小时", "remainingPercent": 82, "resetsAt": 1795435200 }
  ],
  "extraProviders": [
    { "id": "workbuddy", "name": "WorkBuddy", "valueText": "2,500 积分", "statusText": "今日已签 · 10:00" }
  ]
}
```

## 常见问题排查

- **菜单栏看不到图标**：本应用为纯菜单栏应用（无 Dock 图标）。如使用刘海屏 MacBook 且右侧图标较多，可切换到 `Compact Ring (7D)` 紧凑单环模式，或按住 `⌘` 将图标拖至更靠右位置。
- **刷新失败显示问号**：悬浮卡片会保留上次成功的数据并提示失败原因与重试时间（失败退避 `60s / 120s / 300s`）。查看本机诊断日志：
  ```sh
  /usr/bin/log show --last 30m --style compact --predicate 'subsystem == "io.github.codexusagestatus" AND category == "refresh"'
  ```

---

## English

An unofficial native macOS menu-bar companion for viewing **Codex**, **Gemini / Antigravity**, and optional external tool balances (**WorkBuddy / Trae / Qoder**) at a glance.

- **2×2 hover card**: Top-left shows Gemini chat 5-hour and weekly limits (synced silently via the optional Chrome extension bridge in `integrations/gemini-chat/`, with macOS Accessibility fallback); bottom-left shows Antigravity quotas; top-right shows Codex 5-hour / weekly windows and reset credits; bottom-right shows tabular credit/USD balances for WorkBuddy / Trae / Qoder / AgentRouter.
- **Display styles**: Switch between **Compact Ring (7D)** (`30pt` notch-friendly single ring), **Double Ring**, and **Large Readout**.
- **Privacy & safety**: Codex usage comes exclusively from local `codex app-server` (`account/rateLimits/read`). The app itself never reads credential files, browser cookies, Keychain items, or OAuth tokens. See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).
- **Multi-host lifecycle helper**: Optional per-user listener (`lifecycle/install.py`) keeps the badge running while any configured host app (`ChatGPT.app`, `Gemini.app`, `Antigravity.app`) is active and quits cleanly once all exit.
- **Build & test**:
  ```sh
  npm test
  swift test --package-path macos/CodexUsageStatus
  npm run build:macos
  ```
- **Downloads & releases**: Pre-built ad-hoc signed ZIPs (`arm64` / `x86_64`) are published on [GitHub Releases](https://github.com/Serendipity-Y/ai-usage-status/releases). See [CHANGELOG.md](CHANGELOG.md) for version history.
