# MIRA · AI Task Hub 0.2

## 0.2 界面改版

- 主界面采用暖纸工作台：暖白底色、陶土色强调、宋体标题、顶部「今日 / 计划 / 记录」导航；今日页左侧为 AI 消息，右侧为真实的今日计划。无计划时显示空状态，不填入演示数据。
- 点击菜单栏星形图标展开紧凑面板，可切换待处理与今日计划、打开原任务、延后与标记处理；「查看全部任务」返回完整主界面。
- 独立提醒采用无标题栏圆角卡片，显示任务名称、状态、关闭按钮、延后与高对比主按钮。系统通知获授权后仍遵循系统原生通知样式。
- 右上角菜单栏图标可预览面板，齿轮进入连接与设置。原有数据格式保持兼容。

可运行的 macOS 菜单栏初版，使用 SwiftUI / AppKit，无服务器、无 API Key、无第三方运行依赖。适用于 macOS 13+；当前构建针对本机 Apple Silicon。Windows 尚未实现。

## 桌面定时计划接入

- 启动时和每 30 秒只读同步 `$CODEX_HOME/automations/*/automation.toml`（默认 `~/.codex/automations`），「计划」和设置页可手动同步。已验证本机「每周回顾 · 周五 16:00」。这是本机文件适配，依赖客户端保存格式，不是 ChatGPT 云端 Tasks API。
- 支持每天、每周指定星期的单个固定时刻，采用电脑当前时区。月度、间隔多周、小时循环等尚不支持，会明确显示解析问题，不猜测提醒时间。
- 电脑运行 MIRA 时到点提醒；启动／唤醒后补发当天错过的提醒。同一计划每天只生成一条，完成后重启不重复；未完成保留至当天结束，此后仅在记录中显示，不补弹前几天的事项。
- 同步计划在来源应用修改。暂停／删除会撤下当天未完成提醒；调整时间会更新当天未完成事项。完成仅记录在 MIRA，不会取消源自动化或标记 AI 执行成功。读取失败时保留已有记录并显示原因。
- 本版提醒的是**计划到点**，不是确认源任务已执行。源任务执行结果继续由现有 Codex hooks 通知。未取得可验证的计划专用深链时打开 MIRA 任务中心。
- **ChatGPT 网页／手机端 Tasks 尚未自动接入**。MIRA 本地计划仍可填写 ChatGPT 对话链接；这不等于云端同步。登录自动启动需要在 MIRA 设置中启用。

## DSH（DeepSeek Harness）连接

- 接入方式：在 MIRA 的「连接与设置」点「配置 DSH 连接」，或运行 `bash scripts/install-dsh-bridge.sh`；两者做同一件事——把桥接插件复制到 DSH 桌面 profile 的 `plugins/mira-bridge/`，再往 `cordis.patch.yml` 追加一行 `mira-bridge`。改动前会备份原补丁，其他配置保持不动。
- 轮次与提问事件只观察：`turn/end` 按原因写入本轮结束 / 任务失败 / 已中断 / 已拦截 / 已达上限；`user-questions/request` 写入「待补充信息」，回答或取消后自动关闭。
- 审批（`approval/request`）在 MIRA 存活时会被接管：弹窗给出「允许一次 / 拒绝 / 去 DSH 处理」，决策通过一次性 token 回执（60 秒有效）；超时、关闭弹窗、或选「去 DSH 处理」都会立即交还 DSH 原生对话框。MIRA 不修改会话内容。
- 关闭事件是一条带 `dismiss` 字段的控制条目：MIRA 只关闭对应提醒并删除它，不会显示、不会再次弹窗。审批回执只作用于当前这一条请求，不做「始终允许」。
- 子代理会话（`origin: subagent`）不提醒；同一会话的新事件会把旧提醒标为已处理，与 Codex 的合并规则一致。标题优先取 DSH 已生成的会话标题（`session/title` 或标题服务）；标题还没生成时用首条用户消息的前 32 字作为任务简介；两者都没有才回退为「项目名 · 第 N 轮」。审批与提问提醒同样带上当前轮次。
- 点击提醒打开 `dsh://open`。当前版本的 DSH 深链只聚焦主窗口，没有按会话跳转的参数，所以弹窗同时显示标题和会话短标识，便于回到原窗口定位。
- 只覆盖 DSH 桌面 profile；`dsh web`、`headless` 等 profile 不会加载该插件。应用设置里的「禁用第三方插件」会备份并停用补丁层，需要重新执行安装脚本。
- 卸载：`bash scripts/uninstall-dsh-bridge.sh`。


## 启动验收

双击 `dist/MIRA.app`。关闭窗口不会退出，点击菜单栏星形图标打开紧凑面板，再选「查看全部任务」打开主窗口。

1. 在「连接与设置」点「测试弹窗」。系统通知未授权时显示 MIRA 自己的浮动提醒；授权后使用系统通知，避免重复弹窗。
2. 新建计划，时间设为今天已经过去的时间。保存后应立即补发；点「完成」后重启应用，不应再出现。
3. 新建未来一分钟的计划。退出应用，等过了该时间再启动，当天应补提醒。跨天不追发旧计划。
4. 待确认、待补充信息与个人计划可以选择「10 分钟后」。Codex / DSH 的「本轮结束」通知自动进入记录，不计入待处理，也没有「标为已处理」按钮；仍通知一次并可打开原任务。中断等其他状态仍可手动标记处理。关闭待确认或个人计划弹窗会保留待处理事项。
5. 「连接与设置」→「配置本机连接」。原有 hooks 会保留并备份。然后在 Codex 的 hooks 审核界面审查并信任接收器，启动新会话。CLI 可用 `/hooks` 进行审核。不要绕过 hook 信任。
6. 在新的本地 Codex 会话中完成一轮真实任务。MIRA 应收到「本轮结束」，点击进入原会话。权限请求需用你实际需要审批的任务验收，MIRA 不会自动批准。
7. 在设置启用「登录电脑时启动 MIRA」。macOS 可能要求在系统设置的登录项中允许；以系统最终状态为准。注册前请把 app 放在固定位置。
8. DSH 连接：先启动一次 DeepSeek Harness，再运行 `bash scripts/install-dsh-bridge.sh`。在 DSH 里跑完一轮（或让它报错结束），MIRA 应出现「本轮结束」或「任务失败」。若没有，退出并重新打开 DSH 后再试；`dsh://open` 只会把 DSH 窗口切到前台，不会精确跳到某个会话。
9. DSH 审批：让 DSH 执行一个需要确认的操作，MIRA 弹窗会出现「允许一次 / 拒绝 / 去 DSH 处理」。允许或拒绝后弹窗自动收起；不操作则约 60 秒后回落到 DSH 原生对话框。

## 真实连接范围

- 接收官方 `Stop`、`PermissionRequest`、`UserPromptSubmit`、`Interrupt` hooks。
- `Stop` 表示轮次结束，**不保证整个目标完成或成功**；目前不能可靠区分任务失败。
- `PreToolUse` 对 `request_user_input` 的支持取决于客户端工具覆盖；尚未完成桌面端真实补充信息事件验证。
- hook 只输出 `{}`，不返回批准、拒绝、继续或阻断决定。
- `codex://threads/<session_id>` 在当前安装客户端资源中可确认；是客户端依赖的跳转路径，后续客户端版本可能变化。提供复制标识兜底。
- DSH 走桌面 profile 的第三方插件：把 `turn/end` 的 reason 映射成本轮结束、任务失败、已中断、已拦截、已达上限；审批在 MIRA 存活且有心跳时由弹窗代答（一次性 token、60 秒过期），否则直接回落到 DSH 原生对话框。不修改会话内容。
- DSH 的深链目前只有 `dsh://open`（聚焦主窗口）；弹窗保留会话标题和短标识作为定位兜底。插件只挂载在桌面 profile，`dsh web` / `headless` 不生效。
- 本地用户层 hooks 不能监控个人账号已有云端任务或普通 ChatGPT 对话。桌面计划通过独立文件适配器同步，ChatGPT 云端 Tasks 尚未连接；也可在 MIRA 新建个人计划并粘贴对话链接。
- **配置成功不等于已连通。** 界面直到收到真实 hook 文件才显示最近事件时间。信任审核必须由用户在 Codex 中完成；应用不修改信任记录。
- 事件名称优先使用本地 Codex 元数据中对应会话的可见名称（`name`），兼容旧格式短标题；不可用时回退为项目名与会话短标识。只读查询匹配的会话，不读完整对话、浏览器 Cookie、凭据或完整命令。此适配依赖客户端内部 SQLite 格式，后续版本可能变化。

## 存储与行为

`~/Library/Application Support/MIRA/state.json` 保存计划、记录与去重键，原子写入。`inbox/` 为 hook 原子投递队列；无法解析或链接非法的事件会移入 `inbox/rejected/` 保留原件，不会阻塞后续事件，也不再每 3 秒重复报错。无需 SQLite 即可完成单进程初版；只允许一个应用进程运行。接收器可在应用关闭时写队列，下次启动接收。超过 24 小时的 AI 事件仅归档。每天的计划按本机当前时区、日历日生成一次；有效期到当天午夜。计划编辑影响后续生成，已生成的当天记录保留原内容。

Codex 的「已处理」只关闭 MIRA 提醒，不代表权限已经批准；DSH 的「允许一次 / 拒绝」会把 `allowed-once` / `rejected` 真实回传给当前请求。运行状态来自最近 hook，不是持续心跳；客户端崩溃后可能仍显示运行中。不会在通知中执行模型请求。

DSH 桥接在会话标题缺失时，会保存首条用户消息的前 32 字作为提醒标题（仅这一段，不保存其他对话内容）。MIRA 每 3 秒写一次 `heartbeat`；DSH 只有在心跳新鲜（15 秒内）时才把审批交给弹窗。审批回执写在 `decisions/`（0700 目录、0600 文件、一次性读取），同一用户的其他进程理论上可以伪造回执——这是本地确认机制的边界。收件箱条目支持可选 `dismiss` 字段：值为另一条提醒的 id 时，只关闭那条提醒并丢弃自身，用于审批决定或提问回答后的自动收起。本地 JSON 无无限增长清理策略，适合初期个人验收。系统勿扰可能抑制系统通知，可在任务中心查看保留记录。浮动提醒一次只显示一条，批量事件仍全部进入收件箱。

## 编译与测试

```sh
bash scripts/build.sh
python3 -m unittest discover -s tests -p 'test_*.py'
node --test tests/test_dsh_bridge.mjs
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift tests/CoreTests.swift -o /tmp/mira-core-tests
/tmp/mira-core-tests
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift Sources/ScheduledTasks.swift tests/ScheduledTasksTests.swift -o /tmp/mira-schedules-tests
/tmp/mira-schedules-tests
open dist/MIRA.app
```

依赖 Apple Command Line Tools（Swift）与系统 `/usr/bin/python3`（hook）。构建仅做本机 ad-hoc 签名，未公证，不应将此二进制作为正式公开发行版。

## 移除连接

退出 MIRA 并先在设置关闭登录启动。从 `~/.codex/hooks.json` 中仅删除 command 包含 `MIRA/receive.py` 的 hook 项，保留其他配置；安装前备份位于同一目录 `hooks.mira-backup-*.json`。DSH 连接用 `bash scripts/uninstall-dsh-bridge.sh` 移除插件目录与补丁行，补丁备份在同目录 `cordis.patch.yml.mira-backup-*`。删除 app 即可卸载，数据目录可留存。

## 依据

- [官方 Hooks 事件、信任与执行语义](https://learn.chatgpt.com/docs/hooks)
- [官方桌面插件生命周期 hooks](https://developers.openai.com/plugins/build/plugins)
