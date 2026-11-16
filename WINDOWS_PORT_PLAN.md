# MIRA Windows 迁移方案（v1：不含网页监控）

> 状态：草案，待确认技术栈后进入 M0
> 基线：MIRA 0.2.0 · `5e6efbf` · 2026-11-16
> 本文所有行数、路径、行为均来自对当前仓库的实际核查，非估算。

---

## 1. 结论先行

1. **这不是"重新打包"，是一次真正的移植。** MIRA 的界面层 100% 建在 SwiftUI + AppKit 上，Windows 没有官方对应实现，`swiftc` 编不出可用产物。
2. **UI 不是最大风险，Codex 实时审批桥才是。** 它依赖 Codex 桌面端的 Unix domain socket 和 macOS App Bundle 校验，Windows 上大概率需要整体重新设计（见 R1）。
3. **v1 砍掉网页监控后，待移植 7,275 行 / 总量 11,098 行（66%）。** 砍掉的 3,823 行恰好是耦合 AppKit/WebKit 最深的部分。
4. **推荐技术栈：Tauri 2。** 理由见第 8 节。若你更看重"最快出活、不碰 Rust"，Electron 是合理的备选，代价是 ~150MB 安装包。
5. **人力估算：约 26–41 人日（单人全职 5–8 周）**，不含 Codex 实时审批（列为 v1.5）。

---

## 2. 事实基线

| 项目 | 现状 |
|---|---|
| 语言 / 框架 | Swift 5.x · SwiftUI + AppKit + WebKit |
| 代码量 | 24 个 `.swift` 文件 / 11,098 行 |
| 界面占比 | 约 43%（25 个 `View` 结构体，约 4,800 行，集中在 4 个文件） |
| 逻辑占比 | 约 55%（状态机、计划解析、事件协议、任务模型） |
| 应用形态 | 菜单栏常驻（`LSUIElement=true`），无 Dock 图标，弹出式窗口 |
| 运行时依赖 | 仅系统自带的 `/usr/bin/python3`，无第三方库 |
| 构建方式 | [scripts/build.sh](scripts/build.sh) 单条 `swiftc` 命令 + 手工组装 .app + ad-hoc 签名 |
| 测试 | 8 个 Swift 测试 + 5 个 Python/Node 测试，共 3,317 行 |
| 最低系统 | macOS 13（[Info.plist](Info.plist) `LSMinimumSystemVersion`） |

**关键资产：3,317 行测试。** 这是移植时唯一的客观验收依据，比肉眼比对界面可靠得多。**必须先把它们跑成"黄金标准"，再动 Windows 代码。**

---

## 3. 平台能力映射

| 当前实现 | 位置 | Windows 对应 | 复杂度 |
|---|---|---|---|
| `NSStatusItem` 菜单栏图标 | [App.swift](Sources/App.swift) | 系统托盘（Tray） | 低 |
| `LSUIElement` 隐藏 Dock | [Info.plist:12](Info.plist#L12) | 无任务栏按钮的窗口 | 低 |
| `NSPanel` 待办浮窗 | [App.swift:1281](Sources/App.swift#L1281) | 无边框置顶窗口，贴近托盘 | 中 |
| `UserNotifications` | 全局 | Windows Toast（需 AUMID + 开始菜单快捷方式） | **中高** |
| 通知上的「延后 / 关闭 / 主按钮」 | Views.swift 提醒卡 | Toast 按钮需 `AppNotificationBuilder`，插件通常不暴露 | **高** |
| `SMAppService` 开机自启 | App.swift | 注册表 `HKCU\...\Run` 或任务计划程序 | 低 |
| 唤醒后补发错过的提醒 | App.swift | `powerMonitor` resume 事件 | 中 |
| `NSWorkspace.open` 打开链接 | 多处 | `shell.open`（注意 URL 白名单必须保留） | 低 |
| `NSPasteboard` | 设置页 | 剪贴板插件 | 低 |
| `~/Library/Application Support/MIRA` | [App.swift:118](Sources/App.swift#L118) | `%APPDATA%\MIRA` | 低（但散落 5 处，见 §6.4） |
| `/usr/bin/python3` | [CodexBridge.swift:34](Sources/CodexBridge.swift#L34)<br>[Core.swift:487](Sources/Core.swift#L487) | 无系统 Python | **高**（见 R2） |
| Unix domain socket | `bridge.py` | 无 Unix socket | **高**（见 R1） |
| `WKWebView` × 34 处 | 监控模块 | WebView2 | 已排除出 v1 |

---

## 4. 风险登记册

### R1 · Codex 实时审批桥 —— 最高风险

`integrations/codex/bridge.py` 的实现细节决定了它**无法直接移植**：

| 代码位置 | macOS 专有假设 |
|---|---|
| `bridge.py:124-128` | 连接 `$CODEX_HOME/ipc/ipc.sock`，`asyncio.open_unix_connection` |
| `bridge.py:125-127` | `info.st_uid != os.getuid()`、`S_ISSOCK` 权限校验 |
| `bridge.py:415` | `/Applications/ChatGPT.app/Contents/Info.plist` 计算 build 摘要，用于"验证过的审批类型"白名单 |

**含义：** 这套"实时接管 Codex 审批"的能力，本质是**逆向 Codex 桌面端的私有本地 IPC**。它在 Windows 上能否存在，完全取决于：

1. Codex 桌面端有没有 Windows 版；
2. 它的本地 IPC 是 named pipe、回环 TCP，还是干脆没有。

**对策（按顺序）：**

- **v1 降级**：只保留**事件通知**路径（`~/.codex/hooks.json` → `receive.py` → 事件流 → 提醒）。这条路径是纯文件 + 子进程，跨平台可行。
- **v1.5 能力探测**：写一个探测脚本，在 Windows 上枚举 `%CODEX_HOME%` 下的 IPC 痕迹（named pipe 列表 / 端口 / 日志），确认后再决定实现方式。
- **明确不接受**：为了"功能对齐"去猜 API 或强行模拟，会产生静默错误。

> ⚠️ 这一项必须在动手前确认，否则 M4 可能推翻。

### R2 · Python 运行时

三处硬编码 `/usr/bin/python3`，Windows 上没有等价物：

| 脚本 | 行数 | 用途 |
|---|---|---|
| `integrations/codex/bridge.py` | 422 | Codex IPC 桥（见 R1） |
| `integrations/codex/receive.py` | 200 | Codex hooks 接收器 |
| `integrations/emit/mira_emit.py` | 157 | 通用事件发射 |
| `integrations/emit/emit.js` | 143 | 同上，Node 版 |
| `integrations/dsh/index.js` + `entry.js` | 446 | DSH 插件（**已经是 Node，最易移植**） |

**推荐路径：全面转向 Node.js。** 项目里本来就有 `emit.js`（Node 版发射器），DSH 插件也是 Node。Windows 版只需附带一个 Node 运行时（约 40MB）或用 Tauri sidecar 打包，即可统一三条链路，扔掉 Python 依赖。

**不推荐**：要求 Windows 用户自己装 Python——这是下载页上最劝退的一步。

### R3 · 通知交互能力缺口

macOS 版提醒卡有「延后 / 关闭 / 高对比主按钮」（Views.swift 提醒卡）。

- Windows Toast **支持**按钮，但需要 `AppNotificationBuilder` / `AppNotificationButton`（WinRT），主流框架的 notification 插件通常只封装了"标题+正文"。
- 未注册 AUMID 的未打包应用，Toast 可能**完全不显示**——这是 Windows 上最常见的"通知不工作"原因。
- 专注助手（勿扰模式）会静默吞掉通知，macOS 的"焦点模式"行为类似，需在设置页给出提示。

**对策：**
- M4 先用"点通知唤起主窗口，在窗口内做延后/确认"的降级方案（行为一致，交互少一步）；
- 若要 1:1 还原，需要一个小的原生 helper（C#/C++ 调 WinRT），列为可选增强。

### R4 · 状态字面量即协议

`Entry.status` 存的是**中文字面量**，而且被当作逻辑键使用：

```
待确认(16) 运行中(5) 待补充信息(2) 待完成(2) 本轮结束(1)
新作业 网页更新 新条目 课程公告 已提交 未提交 已截止
```

**含义：** 这些字符串是 `state.json` 的**事实协议**，不是展示文案。Windows 版必须**逐字保留**，不能用 enum 重新映射后另存——否则 macOS/Windows 两份数据无法互相读取，用户迁移会丢数据。

### R5 · 星期语义偏移（高频事故点）

`Plan.weekdays` 用的是 `Calendar` 约定：

| 语言 | 星期日 | 星期一 | … |
|---|---|---|---|
| Swift `Calendar.component(.weekday)` | **1** | 2 | … 7 |
| JavaScript `Date.getDay()` | **0** | 1 | … 6 |
| C# `DayOfWeek` | **0** | 1 | … 6 |

**转换规则：`swiftWeekday = jsWeekday + 1`。** 这个 +1 一旦漏掉，表现是"周一到周日的计划整体错位一天"，而且不会报错——必须由测试锁死（见 §10）。

---

## 5. v1 范围

### 包含（7,275 行）

| 模块 | 文件 | 行数 |
|---|---|---|
| 状态与存储 | Core.swift | 989 |
| 任务模型 | TaskCore.swift | 512 |
| 字段模型 | Tasks.swift | 88 |
| 主界面 | Views.swift | 1705 |
| 任务库界面 | TaskLibraryView.swift | 1076 |
| 应用主体 | App.swift | 1295（需拆分，见 §8） |
| 设置界面 | SettingsView.swift | 343 |
| 概览组件 | TaskOverview.swift | 277 |
| 计划编辑 | PlanEditor.swift | 166 |
| 桌面计划同步 | ScheduledTasks.swift | 142 |
| 事件协议 | AdapterContract.swift | 264 |
| 记录归档 | HistoryRounds.swift | 105 |
| 同步间隔 | SyncInterval.swift | 25 |
| Codex 桥（**降级为事件通知**） | CodexBridge.swift | 288 |

### 排除（3,823 行，34%）

`WebWatch.swift` 803 · `WebWatchBrowser.swift` 497 · `WebWatchView.swift` 618 · `WebWatchHub.swift` 348 · `WebLogin.swift` 253 · `Chaoxing.swift` 480 · `UniCourse.swift` 409 · `UniCourseLogin.swift` 65 · `TeachingSystem.swift` 315 · `WebCookie.swift` 35

> 排除 ≠ 删除。解码时必须**原样保留** `webWatches`、`unicourse`、`chaoxing` 等未知字段，否则 v2 上线时用户配置已丢失（见 §6.3）。

### v1 明确不做

- 网页监控、教学系统（UniCourse / 学习通）接入
- 内置浏览器登录
- Codex 实时审批接管（→ v1.5）
- macOS ↔ Windows 数据自动同步（v1 靠手动拷贝 `state.json`）

---

## 6. 数据结构契约（移植的锚点）

`state.json` 是唯一的跨平台接口，**先把它锁死，后面都是实现细节**。

### 6.1 顶层结构（`HubData`，Core.swift:179）

```jsonc
{
  "schemaVersion": 2,          // 当前 TaskSchema.currentVersion
  "plans": [ ... ],            // 个人计划
  "entries": [ ... ],          // 消息/提醒流
  "seen": [ "..." ],           // 去重键，Swift Set → JSON 数组
  "lastEvent": 1794820076.775, // 可选
  "tasks": [ ... ],            // 任务库
  "taskCategories": [ ... ]    // 分类
}
```

### 6.2 日期编码 —— 已核实

`App.swift:119/121` 明确设置：

```swift
encoder.dateEncodingStrategy = .secondsSince1970
decoder.dateDecodingStrategy = .secondsSince1970
```

实测 `state.json` 中 `"date": 1794820076.775` → 解析为 **2026-11-16 17:07:56 UTC**（Unix 秒，带小数）。

> 注意：**不是** Swift 默认的 `.deferredToDate`（2001-01-01 基准）。若按默认实现，会得到 2057 年——这是个能让人 debug 一整天的坑。

转换：

- JS：`new Date(sec * 1000)`
- C#：`DateTimeOffset.FromUnixTimeMilliseconds((long)(sec * 1000))`

### 6.3 前向兼容规则

`HubData.init(from:)`（Core.swift:196）在 `schemaVersion > 2` 时**直接抛错**，注释写明"不能让新版本数据被旧版本解码后丢字段"。

Windows 版必须实现同样的保护：
- 读到未知 `schemaVersion` → 只读打开，拒绝写回，提示用户升级；
- 读到未知顶层字段 → **原样保留写回**（用 `JsonDocument` / `serde(flatten)` 保留未知键）。

### 6.4 路径解析（当前散落在 5 处）

| 文件 | 位置 | 硬编码 |
|---|---|---|
| [App.swift:118](Sources/App.swift#L118) | Swift | `Library/Application Support/MIRA` |
| `integrations/codex/bridge.py:421` | Python | `Library/Application Support/MIRA` |
| `integrations/emit/mira_emit.py:139` | Python | 同上 |
| `integrations/emit/emit.js:122` | Node | 同上 |
| `integrations/dsh/index.js:34` | Node | 同上 |

**迁移要求：抽成单一函数 `dataDir()`**，按平台返回：

- macOS：`~/Library/Application Support/MIRA`
- Windows：`%APPDATA%\MIRA`（回退 `%LOCALAPPDATA%`）

并保留 `MIRA_DATA_DIR` 环境变量覆盖（现在已有，测试依赖它）。

### 6.5 代码点（Codex hooks 安装）

[Core.swift:487](Sources/Core.swift#L487) 生成的 hook 命令是 shell 字符串：

```swift
"/usr/bin/python3 '" + script.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
```

Windows 上要生成 `"<node.exe>" "<receive.js>"`，并注意 **Windows 命令行引号规则与 POSIX 完全不同**（`"` 转义、路径含空格、反斜杠）。这是 R2 落地时最容易出错的一处。

---

## 7. 逐文件迁移映射

| 源文件 | 行数 | 目标模块（Tauri 2） | 迁移方式 |
|---|---|---|---|
| `Core.swift` | 989 | `src-tauri: model/`, `storage/` | 逐函数翻译 |
| `TaskCore.swift` | 512 | `src-tauri: model/tasks` | 逐函数翻译（含迁移逻辑） |
| `Tasks.swift` | 88 | `src-tauri: model` | 直接翻译 |
| `ScheduledTasks.swift` | 142 | `src-tauri: schedule/toml` | 正则逻辑可原样搬（注意不支持完整 TOML 解析器） |
| `AdapterContract.swift` | 264 | `src-tauri: contract/` | **契约层，先做** |
| `HistoryRounds.swift` | 105 | `src-tauri: storage/archive` | 直接翻译 |
| `SyncInterval.swift` | 25 | 共享常量 | 直接翻译 |
| `App.swift` | 1295 | **拆分**（见 §8） | 重写 |
| `Views.swift` | 1705 | `src: views/` | 按 HTML 设计稿重写 |
| `TaskLibraryView.swift` | 1076 | `src: views/tasks` | 按 HTML 设计稿重写 |
| `SettingsView.swift` | 343 | `src: views/settings` | 重写 |
| `TaskOverview.swift` | 277 | `src: views/components` | 重写 |
| `PlanEditor.swift` | 166 | `src: views/plan` | 重写 |
| `CodexBridge.swift` | 288 | `src-tauri: bridge/` | v1 只保留事件通知 |

**关于 `App.swift`（1295 行）：** 它是一个 God Object —— 同时管托盘、状态机、定时器、通知、UniCourse、Chaoxing、WebWatch、计划同步。**不要照搬结构**，按 §8 拆成 5 个独立模块。

---

## 8. 目标架构（推荐 Tauri 2）

```
mira/
├── src/                        # 前端（HTML/CSS/TS）
│   ├── views/
│   │   ├── today/              # 今日页
│   │   ├── tasks/              # 任务库
│   │   ├── plans/              # 计划
│   │   ├── records/            # 记录
│   │   └── settings/           # 设置
│   ├── components/             # 提醒卡、任务行、时间轴
│   └── lib/
│       ├── state.ts            # 状态订阅（替代 @Published）
│       └── format.ts           # 日期/星期转换（§6.2、R5）
├── src-tauri/                  # 后端（Rust）
│   └── src/
│       ├── model/              # HubData / TaskItem / Plan
│       ├── storage/            # state.json 读写、原子写、归档
│       ├── contract/           # 事件协议 v0.4.0
│       ├── schedule/           # automation.toml 解析
│       ├── bridge/             # hooks 安装、事件接收
│       └── platform/           # tray / toast / autostart / paths
├── integrations/               # Node sidecar（替代 Python）
│   ├── receive.js              # Codex hooks 接收器
│   ├── emit.js                 # 事件发射
│   └── dsh/                    # DSH 插件（几乎原样）
└── fixtures/                   # 从 macOS 导出的 golden state.json
```

**为什么是 Tauri 而不是 Electron：**

| 维度 | Tauri 2 | Electron |
|---|---|---|
| 安装包 | 5–10 MB | 150 MB+ |
| 常驻内存 | ~40 MB | ~200 MB |
| 界面 | 你自己的 HTML/CSS（你已有 `previews/` 20+ 设计稿） | 同 |
| 系统 webview | Windows = WebView2，macOS = WKWebView | 内置 Chromium |
| 托盘/通知/自启 | 插件齐全 | 生态最成熟 |
| 代价 | 后端要写 Rust | 无，全 JS |

**决策依据：** 你的核心诉求是"一个常驻的小工具"。150MB 的安装包和 200MB 常驻内存，和一个菜单栏小工具的定位不匹配；而你 `previews/` 目录下的 HTML 设计稿说明前端技术栈你已经在用了。**如果 Rust 是硬门槛**，Electron 完全可以接受，只是放弃体积优势。

---

## 9. 里程碑

> 估算单位：人日，单人有相关经验；标注的验收标准必须逐条通过才算完成。

### M0 · 契约固化（2–3 人日）

**做：**
1. 从本机导出真实 `state.json`（脱敏）作为 golden fixture，覆盖：空状态 / 只有任务 / 只有提醒 / 混合 / schemaVersion=1 旧格式。
2. 把 §6 的规则写成**跨语言测试**：日期往返、星期 +1、status 字面量、未知字段透传、`schemaVersion` 越界拒绝。
3. 在 macOS 侧跑通现有 3,317 行测试，记录基线。

**验收：**
- [ ] 5 个 fixture 文件入库，含唯一 id 与预期解析结果
- [ ] 日期往返测试：读 → 写 → 读，秒级精度不丢失
- [ ] 星期测试覆盖 Sunday=1 边界
- [ ] 现有测试全绿（记录为基线）

**这一阶段与语言无关**，无论最后选 Tauri / Electron / C#，产物都复用。

### M1 · 骨架（3–5 人日）

**做：** Tauri 项目初始化、托盘图标与菜单、无任务栏按钮的置顶窗口、单实例锁、`dataDir()` 平台层、设置项存储、退出行为。

**验收：**
- [ ] 启动后只在托盘出现，任务栏无图标
- [ ] 点托盘图标弹出/收起窗口，位置贴近托盘
- [ ] 重复启动不产生第二个实例
- [ ] 数据目录读到 `%APPDATA%\MIRA`

### M2 · 数据层（5–8 人日）

**做：** `HubData` 读写、schema 迁移、任务 CRUD、分类管理、筛选/排序/搜索、记录归档与 90 天清理、原子写。

**验收：**
- [ ] M0 的 5 个 fixture 全部正确解码
- [ ] 任务增删改查通过，分类删除后任务回落「未分类」
- [ ] 记录超过 500 条时按月份导出并裁剪，待处理项不清
- [ ] 写到一半断电不损坏 `state.json`（临时文件 + rename）

### M3 · 界面（8–12 人日）

**做：** 今日页、任务库、计划编辑、记录、设置。按 `previews/round3/` 的版式还原（暖纸底、陶土红、宋体标题 + Georgia 数字）。

**验收：**
- [ ] 无数据时显示空状态，不填演示数据
- [ ] 三栏版式在 1280×800 与 1920×1080 下不破版
- [ ] 键盘可达：Tab 遍历、Esc 关闭、Enter 确认
- [ ] 中文字体回退正确（宋体 → 思源宋体 → 系统默认）

### M4 · 系统集成（5–8 人日）

**做：**
1. Toast 通知（注册 AUMID + 开始菜单快捷方式）
2. 「延后 / 关闭」降级实现（唤起窗口处理，见 R3）
3. 开机自启（注册表 Run）
4. 睡眠唤醒后补发当天错过的提醒
5. `automation.toml` 只读同步（`%USERPROFILE%\.codex\automations`）
6. Codex hooks 安装（写 `hooks.json`，命令改为 Node）

**验收：**
- [ ] 卸载后重装，通知仍可显示（AUMID 未失效）
- [ ] 勿扰模式下有明确提示，不静默丢失
- [ ] 改系统时间跨天，重启后仅补发当天
- [ ] `automation.toml` 解析失败时保留已有提醒并显示原因（不误判为删除）
- [ ] 安装 hooks 后 `hooks.json` 其他字段不被破坏，重复安装幂等

### M5 · 分发（3–5 人日）

**做：** NSIS/MSI 安装包、自动更新、版本号、下载页。

**验收：**
- [ ] 干净 Win10 22H2 / Win11 上安装可运行
- [ ] 卸载后 `%APPDATA%\MIRA` 保留（提示用户手动删）
- [ ] 自动更新能检测并安装新版本

**合计：26–41 人日**

---

## 10. 验收标准

### 复用（现有测试，必须全绿）

| 测试 | 覆盖 |
|---|---|
| `tests/CoreTests.swift` | 状态机、去重、过期 |
| `tests/TaskLibraryTests.swift` | 任务 CRUD、筛选排序 |
| `tests/ScheduledTasksTests.swift` | TOML 解析、不支持规则的报错 |
| `tests/test_contract_parity.py` | **事件协议跨实现一致性** |
| `tests/test_receiver.py` / `test_codex_bridge.py` | 接收器行为 |

### 新增（Windows 专属）

- [ ] 路径解析：`MIRA_DATA_DIR` 覆盖、`%APPDATA%` 回退
- [ ] 日期：`secondsSince1970` 往返，含小数秒
- [ ] 星期：Swift 1–7 ↔ JS 0–6 双向映射
- [ ] 未知字段透传：写回后原字段仍在
- [ ] `schemaVersion` > 2 时拒绝写入
- [ ] 通知 AUMID 注册成功
- [ ] 托盘/开机自启在用户非管理员权限下生效（**不要要求管理员权限**）

### 双平台一致性

- [ ] 同一份 `state.json` 在 macOS 与 Windows 上读写后，语义一致（可加一次往返 diff）
- [ ] 两边生成的 hook 命令各自可用

---

## 11. 分发与下载页

### 安装包

- 格式：**NSIS `.exe`**（推荐，体积小、无管理员权限要求）；企业场景再补 MSI。
- 架构：先出 x86_64，Windows on ARM 通过 x64 模拟运行，v1 不做原生 arm64。
- 最低系统：Windows 10 1809+（WebView2 要求）。

### 代码签名（关键）

从网上下载的未签名 `.exe`，Windows 会弹出 **"Windows 已保护你的电脑 / 未知发布者"** 的 SmartScreen 拦截——这是下载转化最直接的杀手。

| 方案 | 成本 | 效果 |
|---|---|---|
| 不签名 | 0 | 每次下载都拦截，需点"仍要运行" |
| OV 证书 | ~$200–400/年 | 需积累下载声誉，初期仍可能拦截 |
| EV 证书 | ~$400–700/年 | 立即获得信任，无拦截 |

**建议：** 先不签名，在下载页明确写一句说明（"首次运行 Windows 可能提示未知发布者，点『更多信息 → 仍要运行』"），等有稳定用户量再买证书。

### 下载页

- 并排放 **Download for macOS** / **Download for Windows**，**不要按 UA 自动跳转**——用户常在自己的机器上下载给另一台机器用。
- 每个按钮标注：版本号、系统要求、文件大小、SHA-256。
- 提供"如何验证校验和"的一行说明。

### 双平台数据（v1 约束）

v1 **不做**自动同步。`state.json` 手动拷贝可互通（格式相同）。下载页需注明：macOS 与 Windows 各自的 `state.json` 独立，网页监控配置（v1 不支持）不会出现在 Windows 版。

---

## 12. 待你决定

| # | 问题 | 影响 |
|---|---|---|
| 1 | 技术栈：Tauri 2 / Electron / C# WinUI 3 | 决定 M1 之后全部工作 |
| 2 | v1 是否接受「通知里不能直接延后，需唤起窗口」 | 影响 M4 工作量，差约 3–5 人日 |
| 3 | Codex 实时审批是否接受推到 v1.5 | 若必须 v1 就有，需先做 R1 探测，工期不可控 |
| 4 | 是否有 Windows 机器 / 虚拟机可做测试 | 没有的话 M4/M5 无法验收 |
| 5 | 是否愿意为签名付费 | 影响首批用户下载转化 |

---

## 13. 不建议做的事

1. **不要尝试用 Swift + Win32 绑定做 Windows 版。** `SwiftWin32` 只是薄封装，SwiftUI 的视图系统在上面不存在；`OpenSwiftUI` 项目自述处于早期阶段且用了大量私有 API，官方明确不建议用于生产。
2. **不要先做网页监控。** 它占 34% 代码、耦合 WebKit 最深，且是 v1 最不需要的能力。
3. **不要为了"复用"把 Swift 逻辑编译成库给 Windows 调用。** 跨语言 FFI + ABI 稳定的成本，远高于把 6,000 行逻辑重写一遍。
4. **不要照搬 `App.swift` 的 God Object 结构。** 那是 macOS 快速迭代的产物，不是可移植的架构。
