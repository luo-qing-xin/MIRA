# MIRA 适配器契约 · `mira.adapter/1`

适配器只做一件事：把某个客户端的事件翻译成下面的 JSON，交给 SDK 落盘。
**归一化、标题裁切、去重、链接校验、状态文案全部在 MIRA（Swift）里做一次**，
所以接入新工具时不需要重新实现一遍提醒规则。

协议版本由 SDK 写入 `adapter.version`，当前 `0.4.0`；MIRA 见到更低的版本会
在设置页提示更新，见到 `protocol` 不认识的事件会直接忽略（向前兼容）。

## 传输

SDK 的 `deliver` / `emit` 负责：

- 补上 `protocol`、`adapter.version`、`time`（缺省为当前毫秒）；
- 把 `hint` 裁成首段、压成一行、最多 160 个字符；
- 以原子写落进 `<MIRA 数据目录>/inbox/`，目录 0700、文件 0600。

适配器不直接写文件，也不接触 `state.json`、审批回执或标题缓存。

## 信封

```json
{
  "protocol": "mira.adapter/1",
  "adapter": { "id": "dsh", "name": "DSH", "version": "0.4.0" },
  "kind": "turn.end",
  "time": 1764400000000,
  "session": "session-id",
  "turn": 3,
  "cwd": "/Users/x/MIRA",
  "titleHint": "把设置页的按钮改成…",
  "title": "会话可见标题",
  "reason": "completed",
  "link": "dsh://open",
  "dedupeKey": "turn:session-id:3:end:completed",
  "closes": "approval:session-id:token",
  "approval": { "token": "uuid", "ttlMs": 60000, "tool": "shell", "reason": "…" },
  "questions": [{ "id": "q1", "question": "是否继续？" }]
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `protocol` | SDK 写入 | 固定 `mira.adapter/1` |
| `adapter.id` | 是 | 稳定标识，小写，如 `codex`、`dsh`、`claude-code` |
| `adapter.name` | 否 | 界面显示名，缺省用 `id` |
| `adapter.version` | SDK 写入 | SDK 版本，用于设置页的版本自检 |
| `kind` | 是 | 见下表 |
| `session` | 是 | 客户端会话 id；同一会话的新事件会关掉旧提醒 |
| `turn` | 否 | 轮次；0 或缺失表示没有轮次 |
| `time` | SDK 写入 | 事件时间，Unix 毫秒 |
| `cwd` | 否 | 工作目录；MIRA 取最后一段作为项目名 |
| `titleHint` | 否 | 用户这一轮的提示词原文；SDK 裁到 160 字符，MIRA 再清洗并裁成提醒标题 |
| `title` | 否 | 客户端已有的可见标题（会话名等），只在没有 `titleHint` 和缓存时使用 |
| `reason` | `turn.end` 必填 | `completed` / `error` / `aborted` / `blocked` / `max-tokens` / `interrupted`，未知值按 `completed` |
| `requiresPlanCheck` | 否 | Codex 明确处于执行模式时，`turn.end` 可带 `false`，让本轮结束提醒直接发送。缺省时仍核对计划审批 |
| `link` | 否 | 点击提醒打开的深链；必须通过 MIRA 的白名单（ChatGPT、`codex://threads/`、`dsh://open`） |
| `dedupeKey` | 否 | 同一次事件重复投递时的稳定键；缺省由 `session` + `turn` + `kind` 生成 |
| `closes` | `*.closed` 必填 | 要关闭的那条提醒的 `dedupeKey` |
| `approval` | `approval.asked` 可选 | `token` 存在且合法时 MIRA 才代答；`ttlMs` 缺省 60 秒 |
| `questions` | `question.asked` 可选 | 第一题的 `question` 进入提醒正文 |

未知字段会被 SDK 丢弃，未知 `kind` 会被 MIRA 忽略并消费掉，不会让旧版本报错。

## kind 与提醒

| kind | 状态 | 行为 |
|---|---|---|
| `turn.start` | 运行中 | 今日页「正在进行」，不通知 |
| `turn.end` | 本轮结束 / 任务失败 / 已中断 / 已拦截 / 已达上限 | 通知一次，然后进入记录 |
| `approval.asked` | 待确认 | 有合法 `token` 时弹可操作卡片，60 秒后可回落 |
| `question.asked` | 待补充信息 | 提醒用户回到原会话回答 |
| `approval.closed` | — | 静默关闭 `closes` 指向的提醒，自身不显示 |
| `question.closed` | — | 同上 |

## 写一个适配器

以 Python 为例（Node 见 `integrations/emit/emit.js`）：

```python
import mira_emit

def on_event(payload):
    mira_emit.deliver({
        "adapter": "claude-code",
        "name": "Claude Code",
        "kind": "turn.end",
        "session": payload["session_id"],
        "cwd": payload.get("cwd"),
        "hint": payload.get("prompt"),
        "reason": "completed",
        "link": "claude://session/" + payload["session_id"],
        "dedupeKey": "turn:" + payload["session_id"] + ":" + payload["turn_id"],
    })
```

需要写的只有字段映射；标题、去重、状态文案、链接校验和落盘都由共同代码完成。
