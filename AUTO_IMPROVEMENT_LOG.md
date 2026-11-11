# MIRA 持续改进日志

> 本文件是自主改进循环的断点恢复入口。每轮记录：发现、证据、修改、验证、风险、后续。

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

## 4. 恢复入口

```sh
cd /Users/yunye/MIRA
bash scripts/build.sh
python3 -m unittest discover -s tests -p 'test_*.py'
node --test tests/test_dsh_bridge.mjs
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift tests/CoreTests.swift -o /tmp/mira-core-tests && /tmp/mira-core-tests
```

下一项：Q18（Codex hooks 备份冲突）与 Q19（成功提示误用红色错误条），随后全量回归。
