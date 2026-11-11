# MIRA 持续改进日志

> 本文件是自主改进循环的断点恢复入口。每轮记录：发现、证据、修改、验证、风险、后续。原名为 `AUTO_IMPROVEMENT_LOG.md`，R9 起按任务要求改为现名；R1–R8 的历史记录完整保留。

## 0. 项目定位与现有功能清单

MIRA · AI Task Hub 0.2：macOS 菜单栏 AI 任务提醒中心。本地优先，无服务器、无 API Key；用 Codex hooks 与 DSH 桥接插件把「任务完成 / 需要确认 / 需要补充信息」变成可操作的提醒，并维护个人计划提醒。

| # | 功能 | 预期行为 |
|---|---|---|
| 1 | Codex 连接 | 写入 `~/.codex/hooks.json`（Stop / PermissionRequest / UserPromptSubmit / Interrupt / PreToolUse·request_user_input），保留并备份原配置；hook 只投递事件，不返回决定 |
| 2 | Codex 事件接收 | `receive.py` 规范化后原子写入 `~/Library/Application Support/MIRA/inbox/`，只存会话/标题/状态，不存命令与凭据 |
| 3 | DSH 连接 | 设置页或脚本把桥接插件写入桌面 profile，补丁层追加 `mira-bridge`；观察 `session/event` 与 `user-questions/request`；MIRA 存活且心跳新鲜时接管审批弹窗，否则回落到 DSH 原生对话框 |
| 4 | DSH 事件 | `turn/end` → 本轮结束/任务失败/已中断/已拦截/已达上限；`approval/request` → 待确认（一次性 token，60 秒）；`user-questions/request` → 待补充信息；决定/回答后写 `dismiss` 控制条目关闭提醒 |
| 5 | 提醒展示 | 系统通知（已授权）或应用内浮窗；菜单栏面板；主窗口「今日 / 计划 / 记录 / 设置」 |
| 6 | 个人计划 | 每日或每周、当天错过补发、午夜过期、完成/停用/删除、编辑、10 分钟延后 |
| 7 | 历史与去重 | 事件按 id 去重；同会话新事件把旧提醒标为已处理；超过 24 小时的事件直接归档 |
| 8 | 设置 | Codex 连接配置/更新、DSH 连接配置/移除、通知授权、登录启动、测试弹窗、打开数据目录 |
| 9 | 运行方式 | 菜单栏常驻（LSUIElement），单实例；`state.json` 原子写；关闭窗口不退出 |

## 1. 基线（2026-11-11 12:47）

- Git：`main` 已有 4 个提交（基线 + DSH 标题/审批），工作区干净。
- 构建：`bash scripts/build.sh` 成功（ad-hoc 签名）。
- 测试：Python 7 项通过；Node 28 项通过；Swift 断言通过（URL 白名单、dismiss、DSH 安装/移除）。
- 运行：MIRA.app 已构建；本机 `~/.dsh/profiles/desktop` 的安装状态未在本次改动中触碰。
- 已知且有文档的边界：DSH 深链只聚焦窗口；ChatGPT 云端任务不同步；历史不自动清理；每批只弹一个浮窗。

### 1.1 交接基线（2026-11-11 16:07）

- 工作区已有一批未提交的「桌面定时计划同步」功能：`Sources/ScheduledTasks.swift`、计划页/设置页入口、README 与测试。上一轮会话在提交前中断。
- 先按现有测试验证：Python 11 项、Node 29 项、Swift 核心与计划两套断言、`scripts/build.sh` 全部通过，然后作为独立基线提交 `4791858`，不计入本轮优化。
- 之后每个优化轮次单独提交，保证可单独回滚。基线时的 `OPTIMIZATION_LOG.md` 仍是 R1–R8 的内容。

## 2. 改进队列

| ID | 优先级 | 问题与证据 | 处理 | 状态 |
|---|---|---|---|---|
| Q1 | P1 | 收件箱里任一 JSON 解码失败或链接非法时，`tick` 只写错误横幅、文件永不清理，每 3 秒重复报错（App.swift catch 分支） | 移入 `inbox/rejected/` 隔离并保留原件 | ✅ R2 |
| Q2 | P1 | 补丁层为 `[]`（官方推荐的禁用写法）时，安装会直接追加行，产生非法 YAML，DSH 无法启动（`DSHLink.install`） | 识别空层并替换 | ✅ R1 |
| Q3 | P1 | `DSHLink.remove` 在补丁行格式被改过、无法精确移除时仍删除插件目录，补丁仍引用缺失模块 → DSH 启动失败 | 先改补丁并复核，无法复核则抛错保留目录 | ✅ R1 |
| Q4 | P0/P1 | `PlanEditor` 用 `date(bySettingHour:)!` 强制解包；夏令时跳变时该时刻可能不存在 → 打开计划编辑器崩溃 | 增加安全构造与回退 | ✅ R3 |
| Q5 | P3 | `DSHLink.installed` 用子串匹配，`id: mira-bridge-2` 会被误判为已安装 | 改为整行匹配 | ✅ R1 |
| Q6 | P3 | 备份文件名精确到秒，同一秒内两次安装/移除会覆盖上一份备份 | 冲突时追加序号 | ✅ R1 |
| Q7 | P3 | `receive.py` 对 `cwd=/` 生成空项目名，显示为 `Codex · ` | 空名回退 | ✅ R5 |
| Q8 | P3 | `Hub.open` 失败文案只提 ChatGPT/Codex，DSH 用户被误导 | 补上 DSH | ✅ R3 |
| Q9 | P2 | `tick` 每处理一个收件箱文件就整份保存 `state.json`，批量事件时写放大 | 收集后单次保存 | ✅ R2 |
| Q10 | P1 | `installHooks` 对 `Bundle.main.url(forResource:"receive", ...)!` 强制解包，资源缺失时配置连接直接崩溃 | 改为可抛出错误的 guard | ✅ R3 |
| Q11 | P3 | 设置页与安装脚本注释仍写「插件只观察，不参与审批」，与已实现的审批接管矛盾 | 更新为真实行为 | ✅ R3 |
| Q12 | P2 | `Hub.start` 用 `Timer.scheduledTimer` 只进 default 模式；拖拽窗口/菜单跟踪期间提醒轮询暂停 | 注册到 `.common` 模式 | ✅ R4 |
| Q13 | P3 | `receive.py` 把 `session_id: null` 变成字符串 `"None"`；非字符串 `cwd` 会抛异常丢失事件 | 类型与空值守卫 | ✅ R5 |
| Q14 | P2 | 卸载脚本末尾 `"已删除 $DEST。…"` 中变量名与中文标点粘连，`set -u` 下每次卸载都以 unbound variable 退出 | 改为 `${DEST}` | ✅ R1 |
| Q15 | P2 | 应用与脚本的安装注释不同，卸载互不识别；`remove` 删除补丁块时会把后续行粘到上一行 | 双向识别已知块 + 按块替换并复核 | ✅ R1 |
| Q16 | P3 | `tick` 保存失败后，若无新事件则下一轮 `changed == false`，不再重试保存，内存状态可能丢失 | 记录未完成保存，下轮重试 | ✅ R4 |
| Q17 | P2 | DSH 审批提醒投递失败（收件箱不可写）时仍等待 60 秒才回落，期间原生对话框被占住且用户看不到任何提醒 | 投递失败立即交还桌面端 | ✅ R6 |
| Q18 | P3 | Codex hooks 备份名精确到秒，同一秒内重复配置会覆盖上一份备份（与 Q6 同类） | 共用 `Backups.unique` | ✅ R7 |
| Q19 | P2 | DSH 配置/移除/Codex 配置成功时把成功文案写进 `error`，界面用红色错误横幅展示成功 | 新增中性 notice 横幅 | ✅ R7 |
| Q20 | P3 | `Links.valid` 对 scheme/host 大小写敏感，`HTTPS://CHATGPT.COM/...` 等语义等价链接被拒绝 | 比较前统一小写 | ✅ R8 |
| Q21 | P3 | `installed` 不识别 `- id: "mira-bridge"`，卸载时可能误删仍被引用的插件目录 | 接受带引号的 id，未知格式走拒绝分支 | ✅ R8 |
| Q22 | P1 | `tick` 在写盘前把 `notified` 置 true；保存失败时提前返回、未弹提醒，下轮保存成功后该标志已为 true，提醒永久丢失 | 纯函数选择通知 + 失败回滚内存标志 | ✅ R9 |
| Q23 | P1 | 任一桌面计划文件解析失败就把 `scheduleSnapshotComplete` 置 false，所有计划停止 reconcile：暂停/删除/改名可读计划不再撤下或更新提醒 | 记录不可用计划 id，部分快照仍收敛；文件完全不可读时暂停删除判定 | ✅ R10 |
| Q24 | P2 | 卸载脚本在补丁不可读时把它当作「没有 mira-bridge」，仍 `rm -rf` 插件目录；删除后的复核只认无引号行，残留引用不会被发现 | 不可读即拒绝、引号/注释行复核、原子写补丁并保留权限 | ✅ R11 |
| Q25 | P3 | 安装脚本要求补丁文件已存在，与应用「缺失时按空层新建」不一致 | 缺失时创建空层 | ✅ R11 |
| Q26 | P2 | `Inbox.drain` 用 `try?` 吞掉收件箱列举失败，事件静默不处理且界面无错误；运行中删除收件箱不会重建 | 报告错误、非目录拒绝、缺失时以 0700 重建 | ✅ R12 |
| Q27 | P2 | README 承诺关闭审批弹窗立即交还 DSH，但关闭按钮只隐藏面板，DSH 要等 60 秒超时 | 关闭时写 `defer` 决定 | ✅ R13 |
| Q28 | P2 | `Info.plist`/README 声明 macOS 13+，`build.sh` 却按宿主 SDK 盖章（产物 `minos 26.0`），13–25 无法启动 | 显式 `-target ...macos13.0` + 构建后校验 | ✅ R14 |
| Q29 | P3 | 通知权限/hooks/DSH 状态只在启动或应用内操作后刷新；撤销权限后继续发系统通知且无应用内兜底，外部安装后状态陈旧 | 应用激活时重读三项状态 | ✅ R15 |
| Q30 | P2 | DSH 常用确定性 `fallback` 标题（首条消息按字节截断，保留 `#`/「任务：」）；MIRA 原样使用，截图显示为「# 任务：对当前项目进行长期」 | fallback 时优先首条消息首段；清理标题标记；Swift 展示层兼容旧记录 | ✅ R16 |
| — | 跳过 | 桌面计划改到更晚时间时，当天提醒先记为已过期、到新时间再恢复 | 既有 `ScheduledTasksTests` 明确断言该行为，属产品取舍，不擅自改动 | 记录 |
| — | 跳过 | 历史/`seen` 无限增长 | 涉及数据保留语义，需产品决定 | 记录 |
| — | 跳过 | DSH 会话标题在标题生成前回退为短标识 | 已文档化，改动收益低 | 记录 |

## 3. 迭代记录

### R1 · 2026-11-11 · DSH 补丁安装/移除健壮性（Q2/Q3/Q5/Q6/Q14/Q15）

- 根因：安装器把补丁层当纯文本追加，未处理 `[]` 禁用层；行匹配用子串；移除时先删插件目录后不管补丁是否真的清掉；应用与脚本写不同注释块，互不识别；脚本末尾变量与中文标点粘连。
- 修改（`Sources/Core.swift`、`scripts/*.sh`、`tests/CoreTests.swift`）：
  - `installed` 改为整行匹配，`mira-bridge-2` 不再误判。
  - `isDisabledLayer` 识别 `[]` 并在备份后替换为真实列表，避免生成非法 YAML。
  - `remove` 先移除已知块（应用/脚本两种注释），用同一匹配器复核；无法安全移除时抛错并保留插件目录；补丁不可读时也失败退出，不误删插件。去除补丁块不再吞掉后续行的换行。
  - 备份命名冲突时追加 `-2`、`-3`；备份/读取失败不再静默忽略。
  - 两个 shell 脚本同步：整行/正则匹配、`[]` 替换、备份去重、双向识别注释块、移除后复核、`${DEST}` 修复 unbound variable。
- 验证：
  - `swiftc Sources/Core.swift tests/CoreTests.swift` + 运行 → PASS（新增空层替换、脚本块移除、后续行保留、拒绝未知格式、备份去重断言）。
  - `bash -n` 两个脚本通过；临时 `DSH_HOME` 做安装→重复安装→卸载往返、`[]` 层、应用格式块卸载、未知格式拒绝：补丁内容与目录状态均符合预期，退出码 0/1 正确。
  - Python 7 项、Node 28 项通过；`bash scripts/build.sh` 成功。
- 剩余风险：若用户手工把补丁行改成其他 YAML 结构，应用会拒绝移除并提示手动处理（有意为之）；未做整体 YAML 解析，避免引入依赖。

### R2 · 2026-11-11 · 收件箱坏文件隔离与单次保存（Q1/Q9）

- 根因：`tick` 直接在主类里逐个解码并逐个 `save()`；解码/链接校验失败只写错误横幅，文件留在队列里，每 3 秒重复报错；N 个事件产生 N+1 次整份状态写入。
- 修改（`Sources/Core.swift`、`Sources/App.swift`、`tests/CoreTests.swift`、`README.md`）：
  - 新增纯函数 `Inbox.drain`：解码、链接校验、去重、同会话旧提醒归档、24 小时归档集中处理；坏文件移入 `inbox/rejected/`（0700 目录、0600 文件、重名追加序号），返回 `consumed/dismissed/changed/errors`。
  - `Hub.tick` 改为每轮至多保存一次；保存成功后才删除已消费文件；失败则保留文件下轮重试；弹窗/系统通知的关闭延后到保存成功之后，避免「界面已关、状态没落盘」。
  - 删除文件失败不会丢事件：下轮按重复事件消费并重试删除。
- 验证：
  - `swiftc ...` + 运行 → PASS（有效事件入库、旧事件归档、坏链接/坏 JSON 隔离且 0600、dismiss 关闭目标、重复事件不重插、隔离重名不覆盖、drain 不越权删文件）。
  - `bash scripts/build.sh` 成功；Python 7 项、Node 28 项通过。
- 行为兼容性：提醒内容、状态、去重键、24 小时归档、同会话合并规则均未改变；差异仅在坏文件从「永久重试」变为「隔离保留」，以及状态写盘次数减少。
- 剩余风险：批量保存把「每文件提交」改成「每轮提交」；已用 consumed 清单 + 保存成功后才删除来保证崩溃/失败可重试。保存失败后的无新事件重试见 Q16。

### R3 · 2026-11-11 · 崩溃防护与失真文案（Q4/Q8/Q10/Q11）

- 根因：计划编辑器用 `date(bySettingHour:)!` 强制解包，DST 跳变时该墙钟时间可能不存在；`installHooks` 对发行包资源强制解包；设置页仍宣称 DSH 插件「不参与审批」，与已实现的审批接管矛盾；打开失败的提示漏掉 DSH。
- 修改：
  - `Core.swift` 新增 `PlanTime`：用 `matchingPolicy: .nextTime` 取编辑器时间，缺失时刻前移到下一个有效时刻；`components` 对缺失分量回退 0。`PlanEditor` 改用该辅助函数，删除两处强制解包。
  - `installHooks` 资源缺失时抛可读错误，不再崩溃。
  - 设置页 DSH 说明改为真实审批行为；`Hub.open` 失败提示补上 DSH。
- 验证：
  - Swift 断言新增 DST 用例（America/Los_Angeles 2026-03-08 02:30 前移到 03:00；普通 09:15 保持不变）→ PASS。
  - `bash scripts/build.sh` 成功；Python 7 项、Node 28 项通过。
- 行为兼容性：只影响异常/文案路径，正常计划时间与审批流程不变；未改任何界面布局。
- 剩余风险：DST 回拨的重复时刻沿用系统默认 `.first`，与修改前一致。

### R4 · 2026-11-11 · 定时器运行模式与保存失败重试（Q12/Q16）

- 根因：`Timer.scheduledTimer` 只注册 default 模式，窗口拖拽、菜单跟踪等事件跟踪模式下 3 秒轮询暂停，提醒/心跳延迟；`save()` 失败后若下一轮没有新事件，`changed` 为 false，状态永远不会重试落盘。
- 修改（`Sources/App.swift`）：
  - 定时器改用 `Timer(timeInterval:repeats:)` + `RunLoop.main.add(_, forMode: .common)`；启动前先 invalidate 旧定时器。
  - `save()` 成功/失败维护 `savePending`；`tick` 在 `savePending` 时也会重试，成功后清除。`finish`/`snooze`/计划编辑触发的保存失败同样受益。
- 验证：Swift 断言 PASS；`bash scripts/build.sh` 成功；Python/Node 套件不受影响。
- 行为兼容性：轮询仍是 3 秒；只是不再在拖拽/菜单期间暂停。保存成功路径不变，失败路径多一次下轮重试。
- 运行验证限制：本机已有一个旧构建的 MIRA 进程在跑，未强制退出/重启以免打断当前会话；新构建已生成，重启应用后生效。

### R5 · 2026-11-11 · Codex 接收器边界输入（Q7/Q13）

- 根因：`str(payload.get('session_id', ''))` 把 `null` 变成 `"None"`；`Path(cwd or 'Codex').name` 对 `/` 得到空串，来源显示为 `Codex · `；`cwd` 非字符串、`tool_name: null` 会抛异常，事件被 `main` 吞掉；`turn_id: null` 变成 `"None"` 进入去重哈希。
- 修改（`integrations/codex/receive.py`）：
  - 只接受非空字符串 `session_id`（去首尾空白）；缺失或非法直接忽略，不写事件。
  - `cwd` 只接受字符串；根目录、空串、缺失、非字符串统一回退为 `Codex` 来源，标题为 `Codex · 任务 <短标识>`；真实项目名为 `Codex` 时仍显示 `Codex · Codex`。
  - `tool_name` 非字符串按空处理，`PreToolUse` 不再抛异常；`turn_id` 空值不再变成字符串 `"None"`。
- 验证：Python 11 项全部通过（新增缺失/空白 session、null session 不落盘、根目录/空/缺失/非字符串 cwd、真实 Codex 项目名、null tool_name）；`bash scripts/build.sh` 成功；Node 28 项、Swift 断言通过。
- 行为兼容性：正常 payload 的 id、标题、来源、链接、去重规则不变；仅修复异常输入。

### R6 · 2026-11-11 · DSH 审批投递失败快速回落（Q17）

- 根因：`deliver()` 吞掉写收件箱的异常；审批处理器随后仍进入 `waitForDecision`，而 MIRA 根本没收到提醒，只能等 60 秒超时后回落，期间 DSH 原生对话框被挂起。
- 修改（`integrations/dsh/index.js`）：`deliver` 返回是否成功；审批处理在投递失败时立即 `return next()`，不创建轮询定时器、不写 dismissal。
- 验证：Node 29 项通过。新增用例把 dataDir 设为可读但不可写（0500）、MIRA 心跳有效，断言审批立即由桌面端处理、没有启动决策轮询、没有收件箱文件，并记录了 delivery failed 警告。
- 行为兼容性：投递成功的路径完全不变；仅收件箱不可写这一失败路径从「等待超时」变为「立即回落」。

### R7 · 2026-11-11 · 备份去重与成功提示分流（Q18/Q19）

- 根因：Codex hooks 备份名只到秒，重复配置可覆盖原始备份；`installDSH` / `removeDSH` / `installHooks` 把成功文案写进 `error`，主界面用红色错误横幅渲染，成功看起来像失败。
- 修改：
  - `Core.swift` 新增 `Backups.unique(in:stem:extension:)`，`DSHLink.backup` 与 `installHooks` 共用；同名冲突追加 `-2`、`-3`，Codex 备份保留 `.json` 扩展名。
  - `App.swift` 新增 `notice` 状态：配置/移除 DSH、配置 Codex hooks 成功后清空 `error` 并写入中性提示；`Views.swift` 在错误横幅下方增加中性色 notice 横幅，可关闭。
- 验证：Swift 断言 PASS（新增 `hooks.mira-backup-100.json` → `-100-2.json` 扩展名保持、DSH 备份 `-2` 精确命名）；`bash scripts/build.sh` 成功；Python 11 项、Node 29 项通过。
- 行为兼容性：不新增操作流程；按钮、状态行与配置结果不变，仅成功/失败提示的视觉语义分离。
- 剩余风险：notice 与 error 可同时存在（例如先成功再保存失败），两者都可手动关闭；未做自动互斥，避免隐藏真实错误。

### R8 · 2026-11-11 · 链接大小写与带引号插件 id（Q20/Q21）

- 根因：`URL.scheme` / `URL.host` 保留原始大小写，手工填入的 `HTTPS://CHATGPT.COM/...`、`Codex://threads/...`、`DSH://open` 被判为非法；`DSHLink.installed` 只认无引号行，带引号的等价 YAML id 会被当作未安装，卸载时可能在补丁仍引用插件的情况下删除目录。
- 修改（`Sources/Core.swift`）：scheme/host 比较前统一小写；id 匹配接受单/双引号形式。带引号且无法按已知块移除时走既有的「拒绝并保留插件目录」分支。
- 验证：Swift 断言 PASS（新增三种大写链接、恶意后缀仍拒绝，带引号 id 命中、`mira-bridge-2` 仍不命中）；`bash scripts/build.sh` 成功；Python 11 项、Node 29 项通过。
- 行为兼容性：合法小写链接与既有安装格式行为不变；仅接受原本被误拒的等价输入，并避免一种误删。

### R9 · 2026-11-11 · 保存失败不再丢失提醒（Q22）

- 证据：`Hub.tick` 在 `save()` 之前把可提醒条目的 `notified` 置为 true；保存失败时函数直接 `return`，通知/弹窗尚未发出。下一轮 `savePending` 重试成功后，条目仍是 `notified = true`，于是永远不会再提醒。触发条件为写盘失败（磁盘满、权限、数据目录异常）后恢复，属于状态与通知不一致导致的静默丢失。
- 修改（`Sources/Core.swift`、`Sources/App.swift`、`tests/CoreTests.swift`）：
  - 新增纯函数 `Notify.due`（选出 active、未通知、非运行中、未到未来 snooze 的条目）、`Notify.mark`、`Notify.rollback`。
  - `tick` 用 `dueIndices` 选择并标记；保存失败时对同一批索引执行 `rollback`，保留 `savePending`，下一轮重新选出并补发。
  - 未改变正常保存路径、通知顺序或去重键。
- 验证：
  - `swiftc Sources/Core.swift tests/CoreTests.swift` + 运行 → PASS。新增断言覆盖：只选出合格条目、已通知/运行中/未到 snooze/已过期被排除、mark 后不再重复、rollback 后同一批重新变成待通知、`本轮结束` 首次通知一次、空列表安全。
  - `bash scripts/build.sh` 成功；Python 11 项、Node 29 项通过。
  - 另在独立 worktree 中只应用 R9 暂存内容，重新编译并运行 Swift 断言与构建，确认该提交可独立工作。
- 行为兼容性：保存成功时行为完全不变；只有保存失败路径从「静默丢失」改为「下一轮补发」。若写盘持续失败，提醒会持续延迟并在错误横幅提示，不会假装已通知。
- 剩余风险：没有做真实磁盘故障注入（GUI 依赖系统通知中心）；通知选择/回滚不变量已由纯函数测试覆盖。

### R10 · 2026-11-11 · 单个计划文件异常不再冻结全部计划同步（Q23）

- 证据：`Hub.syncSchedules` 把 `scheduleSnapshotComplete` 设为 `snapshot.issues.isEmpty`，`tick` 只有 complete 时才执行 `DesktopSchedules.reconcile`。任一 `automation.toml` 解析失败（例如不支持的月度规则）都会让所有桌面计划停止同步：来源里暂停、删除或改名一个**可读**计划后，MIRA 当天提醒不会撤下或更新，与 README 的承诺矛盾。
- 修改（`Sources/ScheduledTasks.swift`、`Sources/App.swift`、`tests/ScheduledTasksTests.swift`）：
  - `Snapshot` 新增 `unavailable`（存在但无法完整解析的计划 id）与 `removalsAllowed`。
  - `planID` 从原始 TOML 提取 `id`；解析失败但 id 可恢复时只保护该计划，其余计划照常 reconcile。
  - `reconcile` 接受 `unavailable` 与 `allowRemovals`：不可用计划的当天提醒保留，其它已消失计划仍撤下；文件**完全不可读**时 id 不可知，`allowRemovals = false`，该快照只更新已有计划、不删除任何提醒。
  - `Hub` 以 `scheduleLoaded` 区分「同步成功」与「目录列举失败」，替换原来的全局 complete 门槛，并传递 `desktopUnavailable` / `desktopRemovalsAllowed`。
- 验证：
  - 计划测试改为临时目录夹具（不再读取真实 `~/.codex`，测试可重复）。新增：混合快照（可读 + 不支持规则 + 已暂停）、解析失败计划的提醒保留、已暂停计划撤下、文件删除后最终撤下、可读计划在坏文件存在时仍更新、不可读文件阻止删除判定、恢复可读后恢复删除。
  - `swiftc Sources/Core.swift Sources/ScheduledTasks.swift tests/ScheduledTasksTests.swift` + 运行 → PASS；`bash scripts/build.sh` 成功；Python 11 项（R11 新增脚本测试后为 17）、Node 29 项通过。
- 行为兼容性：所有文件正常时行为不变；不支持规则的提醒以前完全停更，现在保留当天已有提醒且不再猜测新时间；不可读文件采用保守策略，不误删提醒。
- 剩余风险：若不可读文件长期存在，已删除计划的提醒会保留到文件恢复可读或删除；这是有意的保守取舍，避免误撤用户提醒。

### R11 · 2026-11-11 · DSH 安装/卸载脚本的失败安全（Q24/Q25）

- 证据：
  - 卸载脚本用 `grep` 判断补丁是否含 mira-bridge；补丁存在但不可读时 `grep` 返回 2，被当作「没有 mira-bridge」，随后仍 `rm -rf` 插件目录，补丁可能仍引用缺失模块 → DSH 启动失败。
  - 删除后的复核只接受无引号整行，`- id: "mira-bridge"` 等残留引用不会被发现。
  - 安装脚本要求补丁文件已存在，而应用安装逻辑允许缺失时按空层新建。
- 修改（`scripts/install-dsh-bridge.sh`、`scripts/uninstall-dsh-bridge.sh`、`tests/test_dsh_scripts.py`）：
  - 安装/卸载在改动前拒绝不可读补丁；安装缺失补丁时创建空层。
  - 卸载后复核改用正则，识别带引号、带缩进/注释的等价 id；仍有残留则退出且不删除插件。
  - 补丁清理改为同目录临时文件 + `chmod` 保留原权限 + `replace` 原子落盘，避免半写补丁导致 DSH 无法启动。
- 验证：
  - 新增 `tests/test_dsh_scripts.py`（6 项，Python 总数 17）：缺失补丁安装并幂等、正常安装→卸载保留无关配置、应用格式块卸载、不可读补丁时安装/卸载均拒绝且插件保留、引用号残留时拒绝且补丁逐字节不变、未知格式拒绝且插件保留。
  - `bash -n` 两个脚本通过；临时 `DSH_HOME` 手工往返（无补丁安装→卸载、引用号残留拒绝、不可读拒绝）符合预期；`bash scripts/build.sh` 成功。
- 行为兼容性：正常安装/卸载输出与语义不变；卸载后补丁仍可能留下一个空行（修改前也如此）；未知格式继续拒绝并保留插件。
- 剩余风险：仍是文本块识别而非完整 YAML 解析；这是既有设计，避免引入第三方依赖。

### R12 · 2026-11-11 · 收件箱不可读时不再静默丢事件（Q26）

- 证据：`Inbox.drain` 用 `(try? contentsOfDirectory) ?? []`，收件箱权限错误、路径被替换为文件或在运行中被删除时都表现为「没有事件」；界面不报错，Codex/DSH 提醒静默停止。
- 修改（`Sources/Core.swift`、`tests/CoreTests.swift`）：
  - 先检查收件箱路径：缺失时以 0700 重建（覆盖运行中误删）；存在但不是目录时返回明确错误。
  - 列举失败写入 `Outcome.errors`，由现有错误横幅显示；坏 JSON/坏链接仍走 `rejected/` 隔离。
- 验证：
  - Swift 断言新增：收件箱路径是普通文件时返回「不是文件夹」且不消费；缺失队列被重建为 0700 目录且无错误。
  - 原有收件箱测试（隔离、批量消费、dismiss、去重、权限）全部继续通过；`bash scripts/build.sh` 成功；Python 17 项、Node 29 项通过。
- 行为兼容性：正常队列处理完全不变；只有在队列本身不可用时才新增错误提示/重建。
- 剩余风险：权限持续错误时同一错误会随每 3 秒 tick 重复显示（这是需要用户处理的配置问题，而非可隔离的坏文件）；未尝试自动修改目录权限。

### R13 · 2026-11-11 · 关闭审批弹窗立即交还 DSH（Q27）

- 证据：README 承诺「超时、关闭弹窗、或选『去 DSH 处理』都会立即交还 DSH 原生对话框」，但 `ReminderView` 的关闭按钮只调用面板 `dismiss`，不写 `defer` 决定；`integrations/dsh/index.js` 的 `waitForDecision` 只能等 60 秒超时，期间 DSH 原生对话框一直被挂起。
- 修改（`Sources/Core.swift`、`Sources/Views.swift`、`tests/CoreTests.swift`）：
  - 新增 `ReminderClose.decision(for:)`：仅当条目有 token 且状态为「待确认」时返回 `defer`，其它提醒返回 nil。
  - 关闭按钮先写入该决定（`Hub.decide` 写 `decisions/<token>.json` 并收起弹窗），再执行 dismiss；辅助说明区分为「交还 DSH」/「保留任务记录」。
- 验证：
  - Swift 断言新增：待确认 + token → `defer`；无 token → nil；有 token 但状态不是待确认 → nil；原有审批决定与 DSH 安装断言继续通过。
  - `bash scripts/build.sh` 成功；Python 17 项、Node 29 项通过。
- 行为兼容性：普通（非审批）提醒的关闭仍只关闭弹窗、保留待处理；审批关闭从「保留待处理并等超时」变为「立即交还并标记已处理」，与 README 一致。
- 剩余风险：若写决定文件失败（权限/磁盘），界面仍会关闭并显示错误，DSH 仍走 60 秒超时回落；这是本地故障路径，未做自动重试。

### R14 · 2026-11-11 · 产物最低系统版本与声明一致（Q28）

- 证据：`Info.plist` 的 `LSMinimumSystemVersion` 是 13.0，README 也声明 macOS 13+；但 `scripts/build.sh` 未传 `-target`，`otool -l` 显示本机构建产物的 `minos 26.0`（SDK 26.4）。macOS 13–25 会拒绝加载该二进制，与对外声明矛盾。
- 修改（`scripts/build.sh`）：
  - 默认目标 `$(uname -m)-apple-macos13.0`，可用 `MIRA_TARGET` 覆盖；构建后读取 `LC_BUILD_VERSION` 的 `minos` 并与目标比较，不一致直接失败。
- 验证：
  - 重新构建 → `otool -l` 显示 `minos 13.0`；`codesign --verify --deep --strict` 通过；构建脚本的校验在正常构建下通过。
  - 全量回归（Python 17、Node 29、两套 Swift、构建）通过。
- 行为兼容性：源码、界面与数据格式不变；只是把产物标记回声明支持的 macOS 13。当前仍只构建本机架构（Apple Silicon 上为 arm64），未做 universal/fat 包。
- 剩余风险：本机是 macOS 26，无法在真实 macOS 13 环境启动验证；可用性依赖编译器在 deployment target 13.0 下对所有 API 的可用性检查（本次编译已通过），但未做旧系统实机验收。

### R15 · 2026-11-11 · 从后台返回时刷新权限与连接状态（Q29）

- 证据：`refreshPermission` 只在启动和点击「授权通知」后调用；`checkHooks`/`checkDSH` 只在启动和应用内安装/移除后调用。用户在系统设置撤销通知权限后回到 MIRA，`notificationStatus` 仍是「已允许」，`tick` 继续只发系统通知；系统会静默丢弃无权限的通知，应用内兜底被跳过，提醒可能丢失。外部运行安装脚本后，设置页也会一直显示旧的「尚未连接」直到重启。
- 修改（`Sources/App.swift`）：`start()` 注册 `NSApplication.didBecomeActiveNotification`，应用回到前台时重读通知权限、Codex hooks 与 DSH profile 状态。三者都是既有的幂等读取。
- 验证：
  - `bash scripts/build.sh` 成功；Python 17 项、Node 29 项、两套 Swift 断言全部通过；未修改任何系统设置或用户连接文件。
  - 未做自动化权限切换（需要改动本机系统通知设置）；人工验收：在系统设置撤销/恢复 MIRA 通知后切回应用，状态应立即更新；在终端运行安装脚本后切回，设置页应显示已连接。
- 行为兼容性：仅在激活时多读三次本地状态；不改变通知授权流程、安装流程或数据。
- 剩余风险：如果 MIRA 一直保持前台时权限被外部撤销（例如 MDM），仍要等到下一次激活才刷新；为保持低开销未加定时轮询。

### R16 · 2026-11-11 · 任务名称改为可读的首段摘要（Q30）

- 证据（用户截图 + 本机会话日志）：
  - 提醒标题为「# 任务：对当前项目进行长期」。对应 DSH 会话 `session-76e34066…` 的 `session/title` 事件在 seq 14 写入 `{"title":"# 任务：对当前项目进行长期","source":{"kind":"fallback"}}`。
  - DSH 的 `fallbackSessionTitle` 用 `maxWords`/`maxBytes` 截断首条消息，保留 Markdown 标题和「任务：」标签；本机该标题正是按字节预算截在「长期」。
  - MIRA 的 `titleOf` 优先采用标题服务的任何 title（包括 fallback），`displayTitle` 只做 `trim + slice(0,80)`；`summarize` 折叠整段 prompt 后按 UTF-16 截断，既没有用于 fallback 场景，也没有清理 Markdown。
- 修改（`integrations/dsh/entry.js`、`integrations/dsh/index.js`、`Sources/Core.swift`、`Sources/Views.swift`、`Sources/App.swift`、测试）：
  - `entry.js` 新增 `cleanTitle`（去 `#`/列表/引用前缀和「任务：」标签）与按码点、词边界的 `clipTitle`；`summarize` 取首条用户消息的**第一段**而非整段 prompt；`displayTitle` 清理并限制 80 码点。
  - `index.js` 的 `titleOf` 识别 `snapshot.source.kind === "fallback"`：优先用首条用户消息首段生成摘要；`session/title` 的 fallback 事件不再写入缓存，避免截断标题被永久钉住；provider/user 标题仍优先并会替换缓存。没有 `source` 的旧版本按原行为使用标题。
  - Swift 新增 `Titles.display` 与 `Entry.displayTitle`，列表、弹窗和系统通知统一使用；只影响展示，不重写 `state.json`，所以旧记录（包括截图这条）立即变干净。
- 验证：
  - Node 35 项通过：新增 `summarize` 首段/清理/词边界、fallback 与 provider 选择、fallback 事件不钉缓存、provider 标题替换缓存、原始标题清理；原有 29 项不回归。
  - Swift 核心断言新增 `Titles.display` 的标题/列表/引用/「任务：」、空清理保留原文、`Entry.displayTitle` 不改写存储标题。
  - 用真实 `state.json` 跑小工具：存储 `# 任务：对当前项目进行长期` → 展示 `对当前项目进行长期`。
  - `bash scripts/build.sh` 成功（`minos 13.0`、签名通过）；Python 17 项、Node 35 项、两套 Swift 断言通过；MIRA 重启为 PID 76710，heartbeat 2.5 秒内更新。
- 行为兼容性：provider/user 标题不变；只在 DSH 标记 fallback 时改用首条消息首段；旧 `state.json` 不迁移，展示即时生效；新条目的标题在入库前已清理。
- 剩余风险/未完成：
  - 本机 `~/.dsh/profiles/desktop/plugins/mira-bridge/` 仍是旧文件（沙箱不允许写工作区外）；MIRA 应用包已包含新 JS，点设置页「更新 DSH 连接」或运行 `bash scripts/install-dsh-bridge.sh` 后重启/热重载 DSH，新会话才会用新逻辑。在此之前新提醒仍可能使用截断标题。
  - 已存在条目的存储标题仍是截断后的文本（显示层只能去前缀，无法补回 DSH 截掉的「自主迭代优化」）；后续新条目会取完整首段。
  - 依赖 DSH `source.kind` 字段；未来 DSH 若移除该字段，会回退到原行为（直接使用标题）。

## 4. 恢复入口

```sh
cd /Users/yunye/MIRA
bash scripts/build.sh
python3 -m unittest discover -s tests -p 'test_*.py'
node --test tests/test_dsh_bridge.mjs
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift tests/CoreTests.swift -o /tmp/mira-core-tests && /tmp/mira-core-tests
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift Sources/ScheduledTasks.swift tests/ScheduledTasksTests.swift -o /tmp/mira-schedules-tests && /tmp/mira-schedules-tests
```

下一项：无新增代码优化；R16 的 DSH 插件文件需用户在 MIRA 设置页点「更新 DSH 连接」（或运行脚本）并重启/热重载 DSH 后，才会对**新**提醒生效；旧记录已通过展示层清理。

## 5. 历史最终验收（R1–R8，2026-11-11 12:58）

- 构建：`bash scripts/build.sh` 成功；`codesign --verify --deep --strict` 通过；`Contents/Resources` 的 `receive.py` / `index.js` / `entry.js` 与仓库源文件 sha1 一致。
- 测试：Python 11 项通过；Node 29 项通过；Swift 断言通过（计划/DST、URL 白名单含大小写、持久化、dismiss、收件箱隔离与批量消费、DSH 安装/移除/备份、审批决定）。
- 脚本：`bash -n` 通过；临时 `DSH_HOME` 覆盖安装→重复安装→卸载、`[]` 层、应用/脚本交叉卸载、未知格式拒绝、后续行保留、备份去重。
- 运行：旧实例已退出，新构建 PID 48925 运行；内存镜像 inode 与磁盘一致；`heartbeat` 每 3 秒更新，说明 `.common` 定时轮询正常工作。
- 数据兼容：`state.json` / 收件箱 JSON 字段未增删，未做迁移；DSH/Codex 安装格式向后兼容（新旧注释块均可卸载）。
- 未做/跳过（需产品或外部条件）：
  - 历史与 `seen` 无限增长、历史页全量渲染：涉及数据保留策略，本次不擅自裁剪。
  - DSH 深链只能聚焦窗口：客户端能力限制。
  - 同一用户的其他进程理论上可伪造审批回执：已文档化的本地机制边界。
  - 未引入 UI 自动化测试；`Hub.tick` 通过 `Inbox.drain` 纯函数测试 + 运行心跳/重启验收覆盖。
  - 每次批量事件只弹一个浮窗：既有设计，未改变。

## 6. 本轮最终验收（R9–R15，2026-11-11 16:25）

- Git：`4791858`（交接基线）→ `f5cc9a7`（R9）→ `b54d344`（R10）→ `d0e65af`（R11）→ `a55b5cc`（R12）→ `d32bfc6`（R13）→ `1aba0a4`（R14）→ `ff10f57`（R15）；本日志的更新单独提交。
- 构建：`bash scripts/build.sh` 成功（ad-hoc 签名）；`otool` 显示 `minos 13.0`；`codesign --verify --deep --strict` 通过；`Contents/Resources` 的 `receive.py` / `index.js` / `entry.js` 与仓库源文件 sha1 一致。
- 测试：Python 17 项（接收器 11 + 脚本安全 6）；Node 29 项；Swift 核心断言（含通知回滚、审批关闭、收件箱错误/重建、链接与 DSH 安装）；Swift 计划断言（含部分快照、暂停、不可读文件）。全部通过。
- 运行：旧实例 PID 64408 已退出；最终构建 PID 73201 运行；`heartbeat` 在重启后 2.8 秒内更新，`state.json` 可正常解析（0 个本地计划、48 条记录、47 个去重键，未迁移/未清理）。
- 数据兼容：`Plan.origin` 只新增可选字段；`Entry` 只新增计算属性，`state.json` / 收件箱 JSON 字段未增删；旧的 `hooks.json` 与 DSH 补丁格式继续兼容。
- 未做/跳过：
  - 桌面计划改到更晚时间时的「先过期再恢复」：既有测试明确断言，属产品取舍，未改。
  - 历史与 `seen` 无限增长、历史页全量渲染：需数据保留策略，未擅自裁剪。
  - DSH 深链只能聚焦窗口：客户端能力限制。
  - 同一用户的其他进程理论上可伪造审批回执：已文档化的本地机制边界。
  - 通知权限撤销/恢复的自动化验证：会改动本机系统设置，留给人工验收（R15 已写明步骤）。
  - macOS 13 实机启动：本机为 macOS 26，已验证产物 `minos` 与 `Info.plist` 一致，未做旧系统实机验收。
  - UI 自动化测试仍未引入；交互修复由纯函数断言 + 构建 + 运行验收覆盖。
  - 每次批量事件只弹一个浮窗：既有设计。

## 7. 用户追问后的补充优化（R16，2026-11-11 16:35）

- 触发：用户给出提醒卡片截图（标题「# 任务：对当前项目进行长期」）并询问名称来源与优化空间。
- 结论：名称不是 MIRA 自拟，而是 DSH 标题服务的确定性 fallback：首条用户消息被按字节预算截断，`#` 和「任务：」原样保留。R16 改为「fallback 时优先首条消息首段 + 清理展示标记」，provider/user 标题仍原样优先。
- Git：`bf9d503`（R16 代码）；本日志与 README 更新随后单独提交。
- 验证：Node 35 项、Python 17 项、两套 Swift 断言、`scripts/build.sh`（`minos 13.0`、签名）全部通过；真实 `state.json` 中的旧条目展示为「对当前项目进行长期」；MIRA 重启为 PID 76710，heartbeat 2.5 秒内更新。
- 仍需用户操作：本机 `~/.dsh/profiles/desktop/plugins/mira-bridge/` 仍是旧文件（沙箱不允许写工作区外）。在 MIRA 设置页点「更新 DSH 连接」或运行 `bash scripts/install-dsh-bridge.sh`，再重启/热重载 DSH；此后新提醒才会使用首段摘要。旧条目的存储文本仍是被 DSH 截断的原名，展示层只能去掉前缀，无法补回缺失文字。


## 8. 方案 03「编辑」主界面改版（R17，2026-11-11 18:20）

- 背景：用户在三个视觉方向中选定方案 03（奶油纸 + 陶土红 + 宋体标题 + 杂志式三栏），要求按此修改主界面。
- 实现：重写 `Sources/Views.swift`；今日页为日期扉页 / 消息流 / 今日安排三栏，新增加载倒计时、来源字符徽标、进行中与本轮结束分区、今日完成环与本周节奏柱。计划页右栏为本周节奏与桌面同步状态；记录页限制正文宽度。`ReminderView`、`PlanEditor`、`SettingsView` 与主题色同步重做；`App.swift` 调整窗口外观（隐藏标题、奶油底、初始 1240×840、最小 1120×740）。
- 行为保持：审批一次性 token、延后、标记处理、打开原任务、计划编辑/删除/启用、记录、DSH 心跳与菜单栏数量提示均未改；数据模型未改，`state.json` 不需要迁移。
- 验证：`bash scripts/build.sh` 成功（`minos 13.0`、ad-hoc 签名）；Swift 核心与计划断言、Python 17 项、Node 35 项全部通过；应用重启为 PID 99533，heartbeat 正常更新。
- 视觉核对：用离屏 `NSHostingView` 将同一套真实视图渲染到 `previews/app-*.png`（演示数据只存在于渲染进程内存，不写 `state.json`）。真实应用仍以本机 `state.json` 启动，未注入演示数据。
- 后续微调：正文与元信息整体放大（宋体 +8%、数字 +6%、界面 +15%）；移除左下角印章；「今日已完成」改为默认展开的下拉区，最多 7 条，超出显示 Show more 并跳转记录页。
- 未做：UI 自动化测试；历史记录仍按既有规则全量展示；未新增菜单栏面板。


## 9. 每轮提示词作为提醒标题（R18，2026-11-11 18:40）

- 触发：用户希望用每一轮提示词作为提醒标题，并询问取首字还是首尾拼接。
- 方案：取提示词首个非空段落，清理 `#`/列表/「任务：」前缀；≤44 字完整保留，超过时取前 28 字 + `…` + 末 12 字。英文按词边界裁剪。短提示词不会加省略号。
- DSH：`latestPrompt` 从会话日志取最近一条 `user/message`，`turn/end`、审批、提问均使用当前轮提示词；只有读不到提示词时才回退到会话标题。
- Codex：`UserPromptSubmit` 把截断后的标题原子写入 `titles/`（0700 目录、0600 文件），本轮后续 Stop / Interrupt / PermissionRequest 复用它；不保存完整提示词，24 小时后过期，turn 不匹配时不用。
- 验证：Node 37 项、Python 20 项、Swift 核心与计划断言、`scripts/build.sh` 全部通过。
- 生效条件：需在 MIRA 设置页点「更新连接配置」和「更新 DSH 连接」，再重启 DSH；旧记录保留原会话标题。


## 10. 正在进行状态带（R19，2026-11-11 18:47）

- 触发：用户希望在今日页上方看到正在进行的任务，并询问这个想法是否合适。
- 设计：放在「等你决定」上方的一条轻量状态带，而不是再做一组操作卡片；最多显示 3 条，含标题、来源、运行分钟和打开入口，不参与通知与待处理计数。无运行任务时整段隐藏。
- DSH：`turn/start` 现在写入一条 `运行中` 条目，不触发通知；同一轮 `turn/end` 到达后，MIRA 按既有同会话规则关闭它。Codex 的 `UserPromptSubmit` 原本就会产生运行中条目，无需新逻辑。
- 验证：Node 38 项、Python 20 项、`scripts/build.sh` 通过；应用重启为 PID 6117。
- 生效条件：DSH 的运行中状态需要点设置里的「更新 DSH 连接」并重启 DSH；Codex 侧无需更新即可看到。
