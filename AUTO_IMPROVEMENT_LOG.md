# MIRA 持续改进日志

> 本文件是自主改进循环的断点恢复入口。每轮记录：发现、证据、修改、验证、风险、后续。

## 0. 项目定位与现有功能清单

MIRA · AI Task Hub 0.2：macOS 菜单栏 AI 任务提醒中心。本地优先，无服务器、无 API Key；用 Codex hooks 与 DSH 桥接插件把「任务完成 / 需要确认 / 需要补充信息」变成可操作的提醒，并维护个人计划提醒。

| # | 功能 | 预期行为 |
|---|---|---|
| 1 | Codex 连接 | 写入 `~/.codex/hooks.json`（Stop / PermissionRequest / UserPromptSubmit / Interrupt / PreToolUse·request_user_input），保留并备份原配置；hook 只投递事件，不返回决定 |
| 2 | Codex 事件接收 | `receive.py` 规范化后原子写入 `~/Library/Application Support/MIRA/inbox/`，只存会话/标题/状态，不存命令与凭据 |
| 3 | DSH 连接 | 设置页或脚本把桥接插件写入桌面 profile，补丁层追加 `mira-bridge`；只观察 `session/event` 与 `user-questions/request`，不参与审批 |
| 4 | DSH 事件 | `turn/end` → 本轮结束/任务失败/已中断/已拦截/已达上限；`approval/asked` → 待确认；`user-questions/request` → 待补充信息；决定/回答后写 `dismiss` 控制条目关闭提醒 |
| 5 | 提醒展示 | 系统通知（已授权）或应用内浮窗；菜单栏面板；主窗口「今日 / 计划 / 记录 / 设置」 |
| 6 | 个人计划 | 每日或每周、当天错过补发、午夜过期、完成/停用/删除、编辑、10 分钟延后 |
| 7 | 历史与去重 | 事件按 id 去重；同会话新事件把旧提醒标为已处理；超过 24 小时的事件直接归档 |
| 8 | 设置 | Codex 连接配置/更新、DSH 连接配置/移除、通知授权、登录启动、测试弹窗、打开数据目录 |
| 9 | 运行方式 | 菜单栏常驻（LSUIElement），单实例；`state.json` 原子写；关闭窗口不退出 |

## 1. 基线（2026-11-11 10:5x）

- Git：`main` 无提交，工作区全部未跟踪；`dist/`、`__pycache__/` 已忽略。
- 构建：`bash scripts/build.sh` 成功（ad-hoc 签名）。
- 测试：Python 7 项通过；Node 19 项通过；Swift 断言通过（URL 白名单、dismiss、DSH 安装/移除）。
- 运行：MIRA.app 已启动；DSH 桥接已安装到 `~/.dsh/profiles/desktop`。
- 已知且有文档的边界：DSH 深链只聚焦窗口；ChatGPT 云端任务不同步；历史不自动清理；每批只弹一个浮窗。

## 2. 改进队列

| ID | 优先级 | 问题与证据 | 处理 | 状态 |
|---|---|---|---|---|
| Q1 | P1 | 收件箱里任一 JSON 解码失败或链接非法时，`tick` 只写错误横幅、文件永不清理，每 3 秒重复报错（App.swift catch 分支） | 移入 `inbox/rejected/` 隔离并保留原件 | 待做 |
| Q2 | P1 | 补丁层为 `[]`（官方推荐的禁用写法）时，安装会直接追加行，产生非法 YAML，DSH 无法启动（`DSHLink.install`） | 识别空层并替换 | 待做 |
| Q3 | P1 | `DSHLink.remove` 在补丁行格式被改过、无法精确移除时仍删除插件目录，补丁仍引用缺失模块 → DSH 启动失败 | 先改补丁并复核，无法复核则抛错保留目录 | 待做 |
| Q4 | P0/P1 | `PlanEditor` 用 `date(bySettingHour:)!` 强制解包；夏令时跳变时该时刻可能不存在 → 打开计划编辑器崩溃 | 增加安全构造与回退 | 待做 |
| Q5 | P3 | `DSHLink.installed` 用子串匹配，`id: mira-bridge-2` 会被误判为已安装 | 改为整行匹配 | 待做 |
| Q6 | P3 | 备份文件名精确到秒，同一秒内两次安装/移除会覆盖上一份备份 | 冲突时追加序号 | 待做 |
| Q7 | P3 | `receive.py` 对 `cwd=/` 生成空项目名，显示为 `Codex · ` | 空名回退 | 待做 |
| Q8 | P3 | `Hub.open` 失败文案只提 ChatGPT/Codex，DSH 用户被误导 | 补上 DSH | 待做 |
| Q9 | P2 | `tick` 每处理一个收件箱文件就整份保存 `state.json`，批量事件时写放大 | 收集后单次保存 | 待评估 |
| — | 跳过 | 历史/`seen` 无限增长 | 涉及数据保留语义，需产品决定 | 记录 |
| — | 跳过 | DSH 会话标题在标题生成前回退为短标识 | 已文档化，改动收益低 | 记录 |

## 3. 迭代记录

（每轮追加：任务、根因、修改、验证命令与输出、提交、剩余风险。）

## 4. 恢复入口

```sh
cd /Users/yunye/MIRA
bash scripts/build.sh
python3 -m unittest discover -s tests -p 'test_*.py'
node --test tests/test_dsh_bridge.mjs
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift tests/CoreTests.swift -o /tmp/mira-core-tests && /tmp/mira-core-tests
```

下一项：Q1。
