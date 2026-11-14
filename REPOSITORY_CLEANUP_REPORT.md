# MIRA 仓库清理报告

日期：2026-11-11 18:57（Asia/Shanghai）
基线提交：`69e06cf docs: note how a DSH rename affects existing reminders`
范围：仓库工作区（`/Users/yunye/MIRA`），保留用户已有未提交修改，不做提交、不执行 reset/clean。

## 0. 结论与指标

本轮按“证据充分、低风险、可回滚”的原则清理，没有改动核心业务逻辑、数据模型或外部接口。

| 指标 | 结果 |
| --- | --- |
| 删除文件 | **6 个**（4 个 Python 缓存、1 个过期打包产物、1 个旧 P0 测试覆盖配置） |
| 删除目录 | **2 个**（`tests/__pycache__`、`integrations/codex/__pycache__`） |
| 合并文件 / 模块 | **0 个文件合并；1 处重复函数逻辑合并**（DSH 的 `firstPrompt` / `latestPrompt` 共用一个扫描函数） |
| 减少代码 | **净减少 37 行**（39 行删除、8 行新增，另删除旧配置 6 行） |
| 受版本管理的文件 | 23 → **22**（删除 `p0-overlay.yml`，尚未提交） |
| 工作区文件 | 52 → **46**（不含 `.git`；加入本报告后为 47） |
| 工作区占用 | 13 MB → **约 12.2 MB / 12,228 KB**（含 `.git`、`dist`、`previews`） |
| 测试 | Node **38/38**、Python **20/20**、Swift 核心与计划两套断言全部通过；构建、签名、启动均通过 |

说明：`previews/`（设计预览，5.9 MB、20 个文件）属于设计过程资料，未被代码、构建或测试引用。按“无法确认处置方式时保留”的原则未删除，只加入 `.gitignore`；如确认不再需要，可再减少 20 个文件和约 5.9 MB。

## 1. 原始项目结构

| 位置 | 职责 | 入口 / 使用方 |
| --- | --- | --- |
| `Sources/App.swift` | 应用入口、`Hub` 状态、通知、菜单栏、窗口、提醒浮窗 | `@main` / AppKit |
| `Sources/Views.swift` | 主界面、今日/计划/记录、完成下拉、运行中状态带、提醒卡 | `HubView`、`ReminderView` |
| `Sources/SettingsView.swift` | 连接与设置页 | `HubView.settings` |
| `Sources/PlanEditor.swift` | 个人计划新建/编辑 sheet | `HubView.sheet` |
| `Sources/Core.swift` | Plan/Entry 数据、调度、收件箱、链接、DSH 安装逻辑 | 全项目 / Swift 测试 |
| `Sources/ScheduledTasks.swift` | 读取 Codex 桌面计划快照 | `Hub.tick` |
| `integrations/codex/receive.py` | Codex hook 接收器：事件 → MIRA 收件箱，写提示词标题 | `.codex/hooks.json` |
| `integrations/dsh/index.js` | DSH 桥接观察者、审批接管、运行中/轮次结束 | DSH 桌面 profile |
| `integrations/dsh/entry.js` | 纯映射：状态文案、标题、条目构造 | Node 测试 / `index.js` |
| `scripts/*.sh` | 构建、DSH 插件安装/卸载 | 人工命令 / Python 测试 |
| `tests/*` | Swift/Python/Node 测试 | 本地测试命令 |
| `dist/` | 本地构建产物（已 gitignore） | 启动验收 |
| `previews/` | 设计过程 HTML 与渲染图（未跟踪） | 仅人工查看 |
| `README.md` / `OPTIMIZATION_LOG.md` / `验收记录.md` | 使用说明、迭代记录、验收历史 | 人工阅读 |

构建入口是 `scripts/build.sh`，运行入口是 `dist/MIRA.app`；没有服务器、数据库迁移或模型权重。

## 2. 发现的冗余与结构问题

### 2.1 低风险、已确认无引用

1. **Python 缓存**：`tests/__pycache__/` 3 个 `.pyc`，`integrations/codex/__pycache__/` 1 个 `.pyc`。其中 `test_installer.cpython-314.pyc` 对应的测试文件已不存在，属于过期缓存。
2. **过期打包产物**：`dist/MIRA-macOS-arm64.zip`（17:13，约 528 KB），早于当前 App（18:57），仓库和文档均无引用；`dist/` 已整体忽略。
3. **旧 P0 覆盖配置**：`integrations/dsh/p0-overlay.yml`，包含本机绝对路径 `/Users/yunye/MIRA/...` 和 `/tmp/mira-p0-inbox`，是早期 P0 手工测试覆盖层；脚本、测试、README 均未引用，当前安装流程直接写 profile 补丁。
4. **未使用的 Swift 代码**：
   - `MiraPrimaryButtonStyle`（`App.swift`）
   - `QuietButtonStyle`（`Views.swift`）
   - `let teal = terracotta`（只被上述未使用样式引用）
   - `Hub.go(_:)`（无调用）
5. **重复的 DSH 提示词扫描**：`firstPrompt` 与 `latestPrompt` 各写了一份相同的 `user/message` 过滤、文本拼接与空值判断逻辑。

### 2.2 属于有意重复，未合并

- `integrations/codex/receive.py` 与 `integrations/dsh/entry.js` 各自实现提示词标题裁剪。两者运行在 Python hook 与 Node 插件两个隔离环境，无共享运行时；强行提取会增加部署依赖。
- `scripts/install-dsh-bridge.sh` / `uninstall-dsh-bridge.sh` 与 `Sources/Core.swift` 的 `DSHLink` 都实现补丁行读写。前者是 CLI 安装路径，后者是应用内安装路径，已有测试分别覆盖；合并会扩大故障面。
- `README.md`、`OPTIMIZATION_LOG.md`、`验收记录.md` 内容有重叠，但分别承担使用说明、开发记录和验收历史，属于可追溯资产，未合并。
- `previews/` 中的概念图与实装截图有视觉重复，但属于设计过程资料，未纳入构建；本轮保留。

### 2.3 结构上的大文件（保留）

- `Sources/Views.swift` 约 1,437 行，`Sources/App.swift` 约 438 行。按视图拆分会改变大量访问级别与状态绑定，无法用现有测试充分证明等价；本轮不做结构性拆分，仅在报告中建议后续按“今日 / 计划 / 记录 / 提醒”拆分并补 UI 冒烟测试。

## 3. 已删除文件及依据

| 文件 / 目录 | 类型 | 引用检查 | 风险 | 依据 |
| --- | --- | --- | --- | --- |
| `tests/__pycache__/test_dsh_scripts.cpython-314.pyc` | 缓存 | 无引用 | 低 | Python 自动生成，可重建 |
| `tests/__pycache__/test_installer.cpython-314.pyc` | 过期缓存 | 无引用 | 低 | 对应源文件已删除 |
| `tests/__pycache__/test_receiver.cpython-314.pyc` | 缓存 | 无引用 | 低 | Python 自动生成，可重建 |
| `integrations/codex/__pycache__/receive.cpython-314.pyc` | 缓存 | 无引用 | 低 | 测试导入时生成，可重建 |
| `dist/MIRA-macOS-arm64.zip` | 过期构建产物 | 文档/脚本无引用 | 低（中） | 早于当前 App，`dist/` 被忽略；本报告记录删除，重新打包即可生成 |
| `integrations/dsh/p0-overlay.yml` | 旧开发配置 | 脚本/测试/文档无引用 | 低（中） | 硬编码本机绝对路径的 P0 临时覆盖层；可从 Git 恢复 |

删除目录：`tests/__pycache__`、`integrations/codex/__pycache__`。

## 4. 已合并 / 重构

**未合并任何文件。** 仅在 `integrations/dsh/index.js` 内部合并重复逻辑：

```js
function scanPrompt(session, newestFirst) { ... }
function firstPrompt(session) { return scanPrompt(session, false); }
function latestPrompt(session) { return scanPrompt(session, true); }
```

- 保持“从旧到新”和“从新到旧”两种扫描顺序完全不变。
- 删除 12 行重复循环，新增 8 行共享函数，净减少 4 行；Node 测试全部通过。
- 同时删除 27 行未使用的 Swift 样式/辅助代码。

## 5. 目录调整前后

没有移动目录或重命名模块。

```text
清理前                              清理后
├── Sources/ (6)                    ├── Sources/ (6, 无文件变化)
├── integrations/                  ├── integrations/
│   ├── codex/__pycache__/  ←删除   │   ├── codex/receive.py
│   └── dsh/p0-overlay.yml  ←删除   │   └── dsh/{entry,index}.js
├── scripts/ (3)                    ├── scripts/ (3)
├── tests/__pycache__/     ←删除     ├── tests/ (4 个源文件)
├── dist/ (app + zip)      ←删 zip   ├── dist/MIRA.app（保留运行）
├── previews/ (20)                  ├── previews/ (20，gitignore)
└── 23 个受版本管理文件              └── 22 个受版本管理文件
```

`.gitignore` 新增 `previews/`，避免设计截图再次进入版本管理；原有 `dist/`、`__pycache__/`、`.DS_Store` 保持不变。

## 6. 修改影响与风险评估

| 修改 | 功能影响 | 风险 |
| --- | --- | --- |
| 删除缓存 | 无；测试时自动重建 | 低 |
| 删除过期 zip | 无；需要时可重新打包 | 低 |
| 删除 P0 overlay | 不影响构建、测试和正常安装；只影响手工 P0 覆盖测试 | 低（中） |
| 删除未使用 Swift 代码 | 编译通过，无引用；不改变界面 | 低 |
| 合并 DSH 扫描函数 | 行为等价，Node 测试通过 | 低 |
| 新增 `.gitignore` 规则 | 只影响 Git 跟踪，不影响运行 | 低 |

没有改动：数据模型、调度逻辑、审批回执、标题规则、UI 布局、外部链接、配置文件格式。

## 7. 验证结果

- `node --test tests/test_dsh_bridge.mjs`：**38/38 通过**。
- `python3 -m unittest discover -s tests -p 'test_*.py'`：**20/20 通过**。
- Swift 核心断言：**通过**（提醒、去重、调度、URL、持久化、DSH 安装、审批决策等）。
- Swift 计划断言：**通过**（桌面计划解析、暂停、星期、过期与身份稳定等）。
- `bash scripts/build.sh`：成功；`otool` 显示 `minos 13.0`；`codesign --verify --deep --strict` 通过。
- 打包资源：`dist/MIRA.app/Contents/Resources/receive.py` 与 `integrations/codex/receive.py` 的 SHA-1 一致。
- 启动冒烟：重新启动 MIRA（PID 6860），`heartbeat` 正常更新（18:57:27）。
- `git diff --check`：无空白错误。
- 未验证：UI 自动化测试仍不存在；没有在本轮重新跑一轮真实的 Codex/DSH 会话，也没有验证 macOS 13 实机启动。以上限制沿用既有验收边界。

## 8. 未处理的高风险问题

1. **`previews/`（5.9 MB）保留**：设计资料，已忽略；是否删除应由你确认。删除不会影响应用，但会失去快速回看设计稿的入口。
2. **`dist/MIRA.app`（3.8 MB）保留**：当前可运行构建，且 README 的验收流程依赖它；`dist/` 已被忽略，可随时重建。
3. **`Views.swift` / `App.swift` 偏大**：拆分需要改变大量视图状态与访问级别，现有测试无法覆盖视觉回归，本轮不做。
4. **跨语言标题裁剪逻辑重复**：Python 与 Node 各自实现，因运行时隔离未合并；后续若规则变化，需要同步修改两处并同时跑两套测试。
5. **安装脚本与应用内 `DSHLink` 重复**：保持 CLI 与应用两条安装路径独立，避免单点故障；未合并。
6. **文档历史重复**：保留 README、优化日志、验收记录三份文档，避免丢失决策上下文。
7. **打包 zip 已删除且没有自动打包脚本**：如需对外分发，建议新增打包脚本或在发布流程中生成；本轮不新增功能。

## 9. 后续维护建议

1. 尽快提交当前工作区（本轮改动叠加在此前未提交的 UI/标题改动之上），避免丢失；提交前运行本报告第 7 节的完整命令。
2. 如不需要设计回看，删除 `previews/`；若需要保留，可移到 `docs/design/` 并作为受控资料，而不是工作区临时目录。
3. 为 `Views.swift` 的拆分单独开一次重构任务，先补 UI 冒烟测试（至少空状态、待确认、运行中、完成下拉、计划页）。
4. 为发布产物增加 `scripts/package.sh`，避免 `dist/*.zip` 成为无法追溯的手工文件。
5. 把跨语言共享的标题规则写成一份可执行测试向量（同一组输入），Node 与 Python 各自引用，降低两处实现漂移风险。
6. 定期清理 `tests/__pycache__`、`integrations/codex/__pycache__`；当前 `.gitignore` 已覆盖，不需要纳入版本管理。

## 10. 回滚与变更记录

- 基线快照：`/tmp/mira-cleanup-backup-185413/`
  - `workspace.tgz`：清理前工作区（不含 `.git`、`dist`）
  - `uncommitted.patch`：清理前未提交改动
  - `git-status.txt`、`tracked-files.txt`：清理前状态清单
- `p0-overlay.yml` 是 Git 跟踪文件，可用 `git checkout -- integrations/dsh/p0-overlay.yml` 恢复。
- 缓存文件包含在 `workspace.tgz` 中，也可由测试重新生成；zip 不在快照内（`dist` 被排除），可由当前 `dist/MIRA.app` 重新打包。
- 本报告不提交任何 Git 变更；所有删除仅作用于工作区。
