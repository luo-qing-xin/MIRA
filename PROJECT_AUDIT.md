# MIRA 项目审查与优化 · 2026-11-12

## 基线与范围

- Git 基线为 `main`，HEAD `09fdeb7f698749f2be22bc42becd01dbd56c8c54`，相对 `origin/main` 领先 17 个提交。开始时有 16 个已修改的跟踪文件、13 个未跟踪文件，暂存区为空。审查以这份实际工作区为准，包含尚未提交的任务库、适配器契约和 Codex 后台确认。逐文件对比初始快照确认，本轮只改动下文列出的源码与测试，并新增本报告。
- 范围覆盖 12 个 Swift 源文件、Codex 与 DSH 接入、两套事件 SDK、3 个脚本、应用清单、现有测试与项目说明。应用是单进程 macOS 菜单栏工具。SwiftUI/AppKit 通过主线程 `Hub` 协调界面、收件箱、调度和原子状态写入。Python/Node 适配器通过本地 JSON 文件投递事件。Codex 后台确认另经本地 IPC 辅助进程处理。没有服务端、远程数据库或网页前端。
- 实机运行基线为只读检查。现有 MIRA 心跳在更新，状态文件为 schema 2，含 4 项任务和 174 条提醒记录。构建、写入失败模拟和合成事件测试均在临时目录运行。现有应用、数据、已安装连接、登录项及仓库内的 `dist` 产物未被本轮替换。未提交或暂存工作区改动。

## A. 功能现状

| 功能模块 | 用途与使用路径 | 实现位置 | 当前状态与依据 | 问题与机会 |
| --- | --- | --- | --- | --- |
| 菜单栏与任务中心 | 从星形图标打开今日页，切换任务库、计划、记录和设置 | [App.swift](Sources/App.swift)、[Views.swift](Sources/Views.swift) | 已实现，构建通过，当前安装实例有心跳 | 新构建的窗口、全屏 Space 和多屏切换未复验 |
| 今日页与提醒 | 聚合待确认、待补充、进行中、今日完成和计划；可打开来源、处理、延后 | [Views.swift](Sources/Views.swift)、[App.swift](Sources/App.swift) | 已实现，Swift 断言覆盖选择、关闭与状态恢复 | 运行中来自事件快照，来源异常退出可能留有旧状态。多条审批同批到达时只有最后一个浮窗可见，其他在主界面 |
| 系统通知与独立弹窗 | 系统授权后使用横幅，未授权时用应用浮窗；带审批操作的提醒使用应用卡片 | [App.swift](Sources/App.swift)、[Views.swift](Sources/Views.swift) | 已实现，状态选择与应用构建通过 | 系统通知异步提交的错误没有向上层反馈；授权、勿扰与失败降级需实机验证 |
| 任务库与分类 | 快速创建，编辑、完成、归档、恢复、删除；搜索、筛选、排序、置顶与自定义分类 | [TaskLibraryView.swift](Sources/TaskLibraryView.swift)、[TaskCore.swift](Sources/TaskCore.swift)、[Tasks.swift](Sources/Tasks.swift) | 已实现，Swift 任务测试与编辑归档写入失败模拟通过 | 截止日可筛选，当前工作台无统一到期视图。删除分类会迁回未分类 |
| 关联链接 | 任务详情关联 ChatGPT、Codex、GitHub 或普通网页，提醒沿用专属白名单 | [TaskCore.swift](Sources/TaskCore.swift)、[Core.swift](Sources/Core.swift) | 已实现，链接检测、非法地址拒绝和持久化有断言 | 系统跳转与第三方应用处理结果本轮未复验 |
| 登录启动与待办浮窗 | 登录时展示最多 5 项未完成任务，可标记完成或进入任务库 | [App.swift](Sources/App.swift)、[TaskOverview.swift](Sources/TaskOverview.swift) | 已实现，任务完成逻辑有测试 | 真实注销／登录、系统登录项状态及浮窗位置未复验 |
| 个人计划 | 创建每日或指定星期提醒，当天补发，完成和重启去重 | [PlanEditor.swift](Sources/PlanEditor.swift)、[Core.swift](Sources/Core.swift) | 已实现，调度断言和写入失败重试模拟通过 | 真实休眠／唤醒未复验 |
| Codex 桌面定时计划 | 定期只读同步本地自动化文件，支持每日和每周固定时刻，暂停或删除时撤回当日待办 | [ScheduledTasks.swift](Sources/ScheduledTasks.swift)、[App.swift](Sources/App.swift) | 已实现支持范围，测试覆盖非法规则和部分读失败时的保护 | 依赖本地 TOML 形态，不支持复杂周期；ChatGPT 云端 Tasks 无自动接入 |
| 收件箱、去重、版本自检 | 投递、旧版事件兼容、标题清洗、无效事件隔离、同会话合并、接入版本状态 | [Core.swift](Sources/Core.swift)、[AdapterContract.swift](Sources/AdapterContract.swift)、[SettingsView.swift](Sources/SettingsView.swift) | 已实现，Swift 入箱与 Python/Node 合约用例通过 | 未知 `kind` 静默消费，未知 `protocol` 目前会尝试旧版解码，和契约说明存在差异 |
| Codex hooks | 观察提示词提交、轮次结束、中断、审批和有条件的补充信息；返回空 JSON | [receive.py](integrations/codex/receive.py)、[App.swift](Sources/App.swift) | 主要路径有进程级测试；桌面补充信息覆盖仍待真实事件验证 | `Stop` 只能确定轮次结束。现有配置更新在混合 hook 组上可能移除其他条目 |
| Codex 后台确认 | 读取待确认快照，展示计划或操作，核对最新内容并提交显式决定 | [CodexBridge.swift](Sources/CodexBridge.swift)、[bridge.py](integrations/codex/bridge.py) | 部分可用。计划提交有既有真实验收记录和本轮模拟；命令、文件、权限回传仅有模拟覆盖，默认仍按客户端构建与验证结果限制 | 私有 IPC 的握手失败、断线恢复和审批日志故障需独立验收 |
| DSH 桌面接入 | 观察开始、结果和提问；MIRA 存活时可代答单次审批，失败或超时交回 DSH | [index.js](integrations/dsh/index.js)、[entry.js](integrations/dsh/entry.js)、[安装脚本](scripts/install-dsh-bridge.sh) | 已实现，模拟覆盖允许、拒绝、延后、超时与投递失败。脚本有临时 profile 测试 | 仅接入桌面 profile；深链聚焦窗口。长会话标题扫描有固定窗口问题 |
| 记录、归档与本地存储 | 原子保存 `state.json`，展示历史，按月导出旧记录，清理派生缓存 | [Core.swift](Sources/Core.swift)、[Core.swift](Sources/Core.swift)、[AdapterContract.swift](Sources/AdapterContract.swift) | 已实现常规路径，覆盖旧状态升级、保留条件和失败重试 | 归档的文本行去重会漏写不同 ID 的记录，见审批 T1 |
| 构建与交付 | Swift 编译，内置 Python/Node 资源，本机 ad-hoc 签名 | [build.sh](scripts/build.sh)、[Info.plist](Info.plist) | macOS 26.4.1 上构建、签名和最低目标版本检查通过 | 仓库没有配置 CI 或原生 UI 自动化。macOS 13 启动和公开分发未验收 |

**架构评价**　Swift 纯逻辑、文件协议和适配器边界适合当前规模，核心路径已有可运行测试。当前主要维护成本集中在 `Hub` 同时协调 AppKit、磁盘、通知和客户端快照，以及应用内与命令行的安装逻辑分开维护。先补边界测试和已复现问题即可，尚无证据支持更换存储技术或大规模拆分界面。

## B. 已完成的代码优化

| 位置 | 原问题与实际修改 | 价值与验证 | 尚存风险 |
| --- | --- | --- | --- |
| [CodexBridge.swift](Sources/CodexBridge.swift) | 每次 Codex 快照都整份写入状态；改为仅在提醒新增、标题变更、关闭或重新打开时保存 | 以 500 条合成记录和 200 个相同快照驱动同一接收入口，写入次数 **200 → 0**。每次基线状态约 379 KB，单次对照耗时约 819 ms → 76 ms。标题变化、请求关闭仍落盘，连接状态与快照时间仍更新 | 本地合成测量，耗时不代表生产机器。IPC 轮询频率和发回客户端的请求保持原有实现 |
| [Core.swift](Sources/Core.swift)、[TaskLibraryTests.swift](tests/TaskLibraryTests.swift) | 老版本读入新版状态后会自动降成当前版本，写回时丢弃未知字段；解码时拒绝超前版本，走现有存储保护 | 原代码回归断言失败。修复后缺省版本仍可迁移；通过实际 `Hub` 读写入口验证，新版状态原文件字节未变 | 遇到超前版本时需使用支持该状态的应用版本 |
| [Core.swift](Sources/Core.swift)、[CoreTests.swift](tests/CoreTests.swift) | 超出记录上限时按数组尾部挑选，晚到的旧事件可能反而被保留；按发生时间挑选最旧的已处理记录 | 原代码在乱序样本上失败。修复后归档选择正确，待处理事项和剩余记录顺序得到保留，同时间仍沿用原先的取舍规则 | Markdown 行身份冲突另需处理 |
| [AdapterContract.swift](Sources/AdapterContract.swift)、[App.swift](Sources/App.swift)、[CoreTests.swift](tests/CoreTests.swift) | 标题缓存只有收到新提示才剪除过期项，写入失败也会清掉待保存标记；现按到期时间检查，失败保留待写标记并在后续轮询重试 | 空闲期间也能执行原定 24 小时过期规则。测试用不存在的目标目录制造写入失败，恢复后验证磁盘记录为空 | 持续磁盘故障期间旧磁盘副本仍会保留，应用会显示保存错误 |
| [PlanEditor.swift](Sources/PlanEditor.swift) | 新建计划第一次保存失败仍留在内存，重试会生成新 ID，可能重复提醒；失败回滚计划数组 | 用目录占据 `state.json` 路径制造失败，恢复后重试只落一条计划 | 真实通知链路仍依赖系统设置 |
| [Tasks.swift](Sources/Tasks.swift)、[TaskLibraryView.swift](Sources/TaskLibraryView.swift) | 详情页归档先保存编辑再单独归档，第二次写入失败仍关闭编辑器；复用任务事务，将两步合为一次保存 | 注入写入失败时任务保持原状；恢复后一次写入同时落盘编辑与归档状态。移除了无调用的旧 Hub 归档入口 | 失败路径通过 Hub 入口验证，未在隔离 GUI 中操作按钮 |

### 验证记录

| 项目 | 基线 | 修改后 |
| --- | --- | --- |
| Python `unittest discover` | 33 项通过 | 使用打包 hook 实际调用的 `/usr/bin/python3` 3.9.6，33 项通过 |
| Node `--test tests/test_dsh_bridge.mjs` | 22 项通过 | 22 项通过 |
| Swift `CoreTests`、`ScheduledTasksTests`、`TaskLibraryTests` | 三套通过 | 三套通过，含新版状态保护、乱序归档及缓存重试 |
| Swift 临时入口探针 | 相同快照重写 200 次 | 相同快照 0 次写入，变更照常落盘；编辑失败回滚与新版状态保护通过 |
| 构建与静态检查 | 临时副本编译、签名及 plist 检查通过 | `scripts/build.sh`、`codesign --verify --deep --strict`、`plutil -lint`、`minos 13.0`、3 个脚本的 `bash -n`、`git diff --check` 均通过 |

新构建 GUI 冒烟未完成。隔离副本直接启动在 AppKit 应用注册阶段退出，经 LaunchServices 启动也被拒绝，虽已核对二进制存在、构建和签名通过。当前运行中的版本有心跳，无法据此推定新版本的 GUI 已验收。本轮也未重跑真实 Codex/DSH 审批、整机登录、休眠唤醒、通知授权及 macOS 13 实机启动。

## C. 产品建议

| ID / 优先级 | 功能与现有问题 | 建议方案与实现 | 用户价值 | 成本 / 风险 | 替代方案 |
| --- | --- | --- | --- | --- | --- |
| F1 / P1 | **并发审批集中处理**。不同会话的审批在一轮轮询中集中到达时，连续创建浮窗会覆盖前一张，短时效请求可能被错过 | 保留一个浮窗，在卡片上提供可操作审批数量和打开待确认列表的入口。复用 `hub.active`，按剩余时间展示，保持逐条人工决策和现有超时 | 同时运行多个 AI 会话时可以看到等待中的请求 | 中 / 中 | 用现有菜单栏计数打开今日页处理，先确认并发请求发生频率 |
| F2 / P2 | **今日到期任务同屏**。个人计划出现在今日安排，已设置截止日的任务要另外到任务库筛选 | 在今日安排引用任务库中今天截止和逾期的少量任务，点击进入现有详情。复用日期筛选与完成规则，无需重复建立计划或增加提醒 | 每天查看一处即可决定先做什么 | 低 / 低 | 继续在任务库用「今天」和「已逾期」筛选。跨页切换频率低时可搁置 |
| F3 / P2 | **历史归档只读查看**。自动整理后，记录页与按月 Markdown 分开查找 | 等 T1 完成后，在记录页加月份选择与只读查看，复用现有文件和系统打开能力，无需导入回主状态 | 找回较早的任务记录时少一次文件定位 | 低到中 / 低 | 现有设置已能打开数据文件夹；偶尔查阅时可直接保留该路径 |

云端 Tasks、复杂周期和新第三方适配器暂不进入推荐实施范围。现有本地计划已经满足固定时刻提醒，新增接入需先明确实际缺口和来源支持。

## D. 审批清单与剩余问题

| ID | 发现与证据 | 建议决策 |
| --- | --- | --- |
| T1 / P1 | **归档会误去重。** `RecordArchive` 用精确到分钟的展示行判重。离线探针让两个不同 ID 的同分钟、同来源、同状态、同标题记录分两批归档，结果只有一行，第二批仍可从主状态移除。[归档实现](Sources/Core.swift) | **建议批准。** 给新写入的归档行保存稳定身份，例如用 Markdown 注释保留 ID；继续读旧表，确认旧行冲突时如何处理，再用临时副本覆盖重复执行及中途失败。成本中、风险中。旧表缺少 ID，无法保证倒推出历史冲突 |
| T2 / P1 | **连接更新可能改动用户 hook。** 当前 Codex 安装器按组删除含 MIRA 命令的组，若同组还有其他命令也会被删除。DSH 的 shell 和应用安装路径对带注释的配置行判定不同，安装插件文件与修改配置也分步进行。[Codex 安装](Sources/App.swift) [DSH 安装](Sources/Core.swift) | **建议批准用临时配置修正和验收。** 按命令项更新 Codex，保留组内其他命令与 matcher；统一 DSH 两条路径的匹配和失败处理。成本中、风险中，真实 profile 安装另外安排 |
| T3 / P1 | **Codex 审批恢复边界。** 握手建立 writer 后如果 initialize 失败，轮询只按 writer 是否为空判断重连；决定日志写入前先占用内存记录，写盘失败可能使尚未发出的请求被当成已提交。[连接与审批](integrations/codex/bridge.py) | **建议先批准协议故障验收。** 用本地模拟 socket 覆盖握手失败、断线和日志失败。保留当前「提交结果不确定时不自动重发」的防重语义，逐项确认实际客户端行为。成本中、风险高。命令、文件、权限回传继续等待真实人工验收 |
| T4 / P2 | **版本契约及长会话边界。** 未知 `protocol` 与文档的处置不一致。DSH 找最近提示词时从前 5,000 个事件的尾部倒查，超长会话可能显示旧提示词。[收件箱解码](Sources/AdapterContract.swift) [DSH 提示词扫描](integrations/dsh/index.js) | **建议暂缓。** 先决定未来协议版本应保留还是消费，再用真实长会话确认事件索引边界。成本低到中、风险中 |
| T5 / P2 | **通知失败反馈与运行验收缺口。** 系统通知异步提交失败时，记录已标记通知；本轮环境无法独立验收原生 GUI、登录和勿扰。[通知入口](Sources/App.swift) | **建议先实机复验。** 确认系统通知失败时应保留待处理、重试还是显示应用内浮窗。成本中、风险中，可能改变用户可感知的提醒行为 |

产品项 F1–F3 和技术项 T4–T5 仍在待讨论清单。

## E. T1–T3 修复记录 · 2026-11-13

| 项目 | 修复与验证 |
| --- | --- |
| T1 | 新归档行在时间单元格的 Markdown 注释中保存可还原的记录 ID，同月按 ID 去重。测试覆盖同分钟同文的不同记录、重复归档及后续月份写入失败后的重试。无 ID 的旧行原样保留。若新记录与旧行同文，仍保留新记录，因此旧文件可能显示同文行。 |
| T2 | Codex 更新保留已有 hook 组和 matcher，只为缺少 MIRA 命令的事件补齐配置。DSH 应用和脚本使用一致的插件行匹配规则，先准备插件再更新补丁，补丁写入失败时恢复原插件。临时配置覆盖混合 hooks、重复更新、带注释和引号的插件行、失效补丁与写入失败。 |
| T3 | Codex 握手失败或断线会释放连接和旧会话状态，再由轮询重连。审批只有在发送意图写入日志后才发送。发送前写入失败可以手动重试，发送后结果不明时继续阻止重复提交。测试用本地 Unix socket 对模拟握手拒绝、超时和断线，并覆盖日志失败与重启后的防重。 |

修正了构建脚本的最低系统版本检查。检查现在读取完整的 `otool` 输出，避免有效二进制因管道提前关闭而被判为构建失败。新版本在临时目录构建和签名，真实 Codex／DSH 配置及运行中的应用仍使用原安装。本轮未重新执行实机审批。
