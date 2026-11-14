# MIRA · AI Task Hub 0.2

## 0.2 界面改版

- 主界面改为暖纸杂志版式：奶油底色、陶土红强调、宋体标题与 Georgia 数字；顶部 `mira.` 字标与「今日 / 任务库 / 监控 / 计划 / 记录」导航，下方三栏为日期扉页、等你决定的消息流、今日安排（时间轴、完成环、本周节奏）。无数据时显示空状态，不填入演示数据。
- 新增「监控」页：给一个网址，MIRA 在内置浏览器里打开页面并识别重复列表；需要登录的页面由用户自己完成登录。新条目可写入任务库，也可以只监控整页变化。不按学校写死域名或接口。
- 今日页顶部用一条轻量状态带展示正在进行的任务（最多 3 条，含运行时长与打开入口），下方优先展示 AI 消息；个人计划只出现在右侧安排，避免重复。计划页右栏为本周节奏与桌面同步状态；记录页按时间倒序排列。
- 独立提醒、计划编辑器与连接设置统一为同一套暖纸样式；提醒卡仍显示任务名称、状态、关闭按钮、延后与高对比主按钮。系统通知获授权后仍遵循系统原生通知样式。
- 本版开始按「每轮提示词」生成提醒标题；更新后需在设置页点一次「更新连接配置」与「更新 DSH 连接」，再重启 DSH，新的标题逻辑才会进入已安装的 hook / 插件。旧记录保留原标题。
- 右上角齿轮进入连接与设置；点击菜单栏星形图标直接打开主界面「今日」页，等待确认或补充信息时图标旁显示数量。原有数据格式保持兼容。

可运行的 macOS 菜单栏初版，使用 SwiftUI / AppKit，无服务器、无 API Key、无第三方运行依赖。适用于 macOS 13+；当前构建针对本机 Apple Silicon。Windows 尚未实现。

## 连接自检与记录整理

- 安装的 Codex 接收器与 DSH 插件所用的 SDK 都会在事件里带 `ADAPTER_VERSION`。设置页按四种状态显示：旧版（文件里没有版本标记）、版本过低（提示点「更新连接配置」或「更新 DSH 连接」）、文件已更新但还需要重启客户端、已是最新并显示最近事件时间。读取的是已安装文件里的常量文本，不执行插件。
- 记录整理在启动和每天首次检查时自动运行：已处理或已过期的记录保留 90 天，本地最多 500 条。超出部分先按月份导出到数据目录的 `records-YYYY-MM.md`，再从 `state.json` 移除。仍待你处理的事项（待确认、待补充信息、待完成）不会被清理。设置页「记录与存储 → 立即整理」可手动执行，并显示当前记录与去重键数量。
- 归档按记录发生的月份分组，标题中的竖线和换行会转义成表格安全的形式；同一批记录重复整理不会重复写入。旧版适配器留下的 `titles/` 目录保留 7 天，无法解析的 `inbox/rejected/` 事件保留 30 天，都由同一次整理顺带清理。

## 任务库

- 顶部导航新增「任务库」。快速添加只要求标题；分类、描述、真实截止日期、重点与置顶都可以稍后在详情里补充。详情支持完成、恢复、归档、删除与编辑，已完成和已归档任务分别进入对应视图，可随时恢复。
- 默认分类为课程、科研、生活、未分类；默认分类固定，自定义分类可新增、重命名和删除。删除自定义分类只会把其下任务移到「未分类」，不会删除任务或关联链接。
- 默认显示未完成任务；支持标题/描述关键词搜索，按分类、状态、重点、截止日期筛选，以及按截止日期、最近更新排序。置顶任务始终排在前面，可在行尾或详情里切换。
- 每个任务可关联多个 ChatGPT、Codex、GitHub 或普通网页链接。任务链接沿用本机链接校验后再交给 `NSWorkspace`；原有提醒/收件箱的链接白名单没有放宽。
- 任务库只使用本地 `state.json`，不连接云服务、不新增 API Key，也不包含每日目标、每日打卡、智能推荐或自动拆解。
- 登录后默认在屏幕右上角弹出「待办浮窗」，不打开整个任务库窗口：最多列出 5 项未完成任务，点圆圈可直接完成，点「打开任务库」再看全部。可在「连接与设置 → 通知与启动」关闭「开机时显示待办浮窗」或点「预览浮窗」。登录启动需要在系统设置的「登录项」中允许 MIRA，且应用应放在固定位置；首次升级会在登录启动尚未开启时请求一次注册。

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
- 每轮开始会写入一条不弹窗的「运行中」状态，用于今日页顶部的「正在进行」状态带；同一轮 `turn/end` 到达后自动关闭。
- 审批（`approval/request`）在 MIRA 存活时会被接管：弹窗给出「允许一次 / 拒绝 / 去 DSH 处理」，决策通过一次性 token 回执（60 秒有效）；超时、关闭弹窗、或选「去 DSH 处理」都会立即交还 DSH 原生对话框。MIRA 不修改会话内容。
- 关闭事件只带 `closes`（旧格式为 `dismiss` 字段）：MIRA 只关闭对应提醒并删除它，不会显示、不会再次弹窗。审批回执只作用于当前这一条请求，不做「始终允许」。
- 子代理会话（`origin: subagent`）不提醒；同一会话的新事件会把旧提醒标为已处理，与 Codex 的合并规则一致。标题按「这一轮」生成：适配器交来该轮提示词的首段（≤160 字符），MIRA 统一清洗并裁成 44 字（头 28 + 尾 12）；读不到提示词时才回退到 DSH 会话标题（`session/title` 的 provider/user 来源）或「项目名 · 第 N 轮」，审批与提问提醒同样使用当前轮次的提示词。已经生成的记录保留创建时标题，不回写状态文件；展示层只清理 Markdown/「任务：」前缀。
- 点击提醒打开 `dsh://open`。当前版本的 DSH 深链只聚焦主窗口，没有按会话跳转的参数，所以弹窗同时显示标题和会话短标识，便于回到原窗口定位。
- 只覆盖 DSH 桌面 profile；`dsh web`、`headless` 等 profile 不会加载该插件。应用设置里的「禁用第三方插件」会备份并停用补丁层，需要重新执行安装脚本。
- 插件与 Codex 接收器共用 SDK 里的 `ADAPTER_VERSION`（当前 `0.4.0`）。设置页据此显示「插件是旧版 → 需要 0.4.0」「插件已更新到 0.4.0 · 重启后生效」或「插件 0.4.0 · 最近事件 …」。这个版本是桥接协议版本，与应用版本号不是一回事。
- 卸载：`bash scripts/uninstall-dsh-bridge.sh`。

## 网页监控（第一、第二阶段）

统一入口在「监控 → 添加教学系统 / 网页」。识别到 UniCourse、666、学习通网址后，可直接在编辑器打开对应专用连接。其他系统在内置浏览器登录，然后配置通用读取规则；不需要学校提供 API。

### 多课程配置

1. 打开课程总览，点「读取此页的课程链接」，勾选需要检查的入口；也可以逐行粘贴网址（最多 40 个）。链接发现只覆盖当前可见页面，不会自动判断哪些链接是课程。
2. 打开一门课程。若课程入口不是直接的作业页，可指认「作业入口」按钮；每个课程会执行一次相同的入口点击。
3. 扫描并选择列表，或通过「列表容器 → 点选」点击条目的空白处，使用其父元素作为列表。标题、截止和状态可点选具体子元素，也可填写相对条目的 CSS 选择器。点「验证当前页字段」核对预览。
4. 配置「下一页」按钮并设置上限（默认 20 页）。终页需要按钮消失、隐藏或禁用；分页重复、超时或达到上限时，本轮不更新任务。
5. 保存后完整遍历所有入口建立基线，首次不发新作业通知。之后新增、明确提交和已知截止时间变化会同步。监控卡显示入口及分页覆盖数量。

同一监控的选定课程共用规则，要求页面结构一致；不同结构需分别配置。支持同源 iframe 的手填框架和字段选择器；跨域 iframe、Shadow DOM、Canvas、无限滚动、复杂多步导航尚不支持。iframe 点选字段暂不支持。尚未用其他学校真实账号验收，不代表已覆盖北大、清华等所有系统。

### 可靠性

- 检查等待导航完成、可见加载提示消失及抽取结果连续稳定；单页等待上限 45 秒。不再固定等待 3 秒后直接采信结果。
- 空列表需有明确空状态文字。任一入口读取失败或登录过期，保留整轮上次结果并显示失败位置，不把不完整结果当成功。
- 仅网页明确显示已提交时自动完成；旧的「条目消失时自动完成」配置不再执行。
- 标题、截止日期变化正确保存；已知截止时间调整生成提醒。临时读不到日期不清空旧日期。优先提取有截止标签的日期，多日期不明确时不猜测。
- 无链接作业在同一课程内标题唯一时，沿用历史身份，延期不新建任务；重名存在歧义时不强行合并。多课程的身份带入口作用域。
- 每次检查成功后才提交结果；检查期间编辑了配置，旧检查结果丢弃。任务库保存失败时不推进已见条目基线。
- 规则和课程网址保存在本机 `web-watches.json`，登录态由 WebKit 保管。MIRA 运行且电脑唤醒时才检查。

第三阶段的 AI 首次识别、通用操作学习和自动改版修复尚未实现。

页面脚本测试：`node --test tests/test_webwatch_script.mjs`。真实 WebKit 测试样本在 `tests/fixtures/webwatch`，`tests/WebWatchBrowserTests.swift` 验证两个课程、四页、延迟加载、同源 iframe 和找不到列表的失败处理；需本机 18763 端口提供该样本目录。

## UniCourse 课程更新

- 连接方式：设置页「UniCourse 课程更新」点「登录 UniCourse」，在 MIRA 自己的窗口里完成 RUC 统一身份认证。MIRA 只取走 `.ruc.edu.cn` 的会话 Cookie，写成本机数据文件夹的 `unicourse.json`（0600）；不保存密码、不上传。登录态过期时状态显示「登录已过期 · 请点『重新登录』」。
- 同步范围：每 30 分钟 / 1 小时 / 2 小时 / 12 小时 / 1 天 / 7 天（默认 30 分钟）从首页拿到课程与 `cno`，再逐门课读取作业页，**只把「未提交」的作业**写进任务库「课程」——标题、作业类型、截止时间（作业页的 `deadline`）和跳转到该作业块的链接。首次同步会把当前所有未提交作业导入一次，之后只提醒新增的。
- 已提交的作业不会进入任务库；你在网页上提交后，下一次同步会把对应任务自动标成已完成（手动完成的保持不变）。公告通过 `morenews` 接口单独提醒，课件和讨论不打扰。
- 去重靠作业页的 `cno` + `hno` 稳定键，存在任务的 `externalKey` 字段里；旧状态没有这个字段时按 nil 解码，重复同步不会生成第二条任务。
- 只在 MIRA 运行时检查（登录启动可以让它常驻）；失败只更新状态，不改动已有任务。首页解析不到课程时在数据文件夹写 `unicourse-diagnostic.html`（0600、页面片段、不含 Cookie），用于页面改版后校准。
- 限制：只读作业页与公告列表，不抓课程详情、不读附件、不代替你提交；作业页若将来改成前端渲染，需要按诊断片段调整解析。

## 学习通作业

- 连接方式：设置页「学习通作业」→「登录 学习通」，在 MIRA 自己的窗口里用手机号/扫码登录。MIRA 只取 `.chaoxing.com` 的会话 Cookie，写成本机数据文件夹的 `chaoxing.json`（0600）；不保存密码。
- 同步范围：调用 `mooc1-api.chaoxing.com/mycourse/backclazzdata` 拿课程/班级，再逐门课读取 `phone/moocAnalysis/workList` 与 `examList` 的 H5 列表。只把「未交」的作业/考试写进任务库「课程」；「已完成」不导入，网页提交后对应任务会自动完成并保留历史；「已过期但未交」仍保留并在备注里标注。列表行里的 `status` 是判断依据（1=未交、2=已过期未交、3=待批阅、4=已完成）。列表里出现「截止时间：…」时写入任务截止日期，没有就留空。
- 去重：优先用链接里的 `workId` / `examId`，没有则用「课程 + 标题 + 链接」的哈希；任务里存 `externalKey = chaoxing:…`。首次同步导入当前所有待做、不逐条通知，之后新增的才提醒。
- 只在 MIRA 运行时同步（30 分钟 / 1 小时 / 2 小时 / 12 小时 / 1 天 / 7 天可选）。首次同步在数据目录留一份 `chaoxing-worklist-sample.html`（0600、不含 Cookie），页面改版后按它校准。
- 限制：适配依赖 H5 列表的 `dt` / `tr` 结构；截止时间只在列表里出现时才能解析；不读作业详情、不代交作业。


## RUC 教学系统（666）

- 连接方式：设置页「RUC 教学系统（666）」→「登录 教学系统」，在 MIRA 窗口里用教学系统账号登录。MIRA 只保存会话 Cookie 到 `teaching.json`（0600），不保存密码。
- 数据来源：666 是 Next.js 应用，未登录请求页面会得到 404 壳；登录后通过两个 Server Action（`listMyCourses` / `listMyExam`）取「我的考试」。MIRA 直接 POST 这两个 action，不渲染页面、不执行页面脚本。
- 只把**未结束**的考试写进任务库「课程」：标题、课程、结束时间、跳转 `/exam/my/<id>`；已结束/已交卷的不进任务库，结束后同步会把对应任务移除。首次同步导入全部待考，之后新增才提醒。
- 同步间隔与另外两个来源一致：30 分钟 / 1 小时 / 2 小时 / 12 小时 / 1 天 / 7 天。
- 限制：依赖当前部署的 action id 与 RSC flight 返回格式；应用升级后可能需要重新对齐。同步失败或读到空课程时，数据目录会留 `teaching-sample.txt`（0600）用于校准。

## 适配器契约与 SDK

- 所有接入方（Codex hook、DSH 插件，以及以后的新工具）只产出一个 `mira.adapter/1` 事件：`adapter`、`kind`、`session`、`turn`、`cwd`、`hint`、`reason`、`link`、`dedupeKey`、审批 token 等字段。完整字段与 kind 表见 [`integrations/contract/adapter-event.md`](integrations/contract/adapter-event.md)。
- MIRA 是唯一接收方：标题清洗与 44 字裁切、状态文案、去重、同一会话合并、链接白名单、24 小时静默规则、审批关闭，全部在 `Sources/AdapterContract.swift` 里做一次；适配器不再自己拼提醒。
- SDK 负责协议信封：`integrations/emit/mira_emit.py` 与 `integrations/emit/emit.js` 统一写入 `protocol`、`adapter.version`（0.4.0）和时间戳，把提示词压成首段并限制 160 字符，再原子写进 `inbox/`（0700/0600）。接入新工具只需要写字段映射，约 40 行。
- 兼容：旧版适配器直接写完整提醒 JSON 的格式仍然接受，混装期间不会丢事件；但旧格式不会获得 0.4.0 的统一标题与去重。设置页的版本检查读的是已安装 SDK 文件（`emit.js` / `mira_emit.py`），更新连接后会提示重启客户端。
- 隐私不变：提示词只保留首段最多 160 字符进入收件箱，MIRA 裁成标题后缓存 24 小时；不保存完整提示词、命令或凭据。

## 启动验收

双击 `dist/MIRA.app`。关闭窗口不会退出，点击菜单栏星形图标直接打开主窗口。

主窗口按当前 Space 显示，允许覆盖全屏应用；点击菜单栏时优先显示在鼠标所在显示器。先把面板带到当前桌面再激活输入，窗口不会固定置顶。

1. 在「连接与设置」点「测试弹窗」。系统通知未授权时显示 MIRA 自己的浮动提醒；授权后使用系统通知，避免重复弹窗。
2. 新建计划，时间设为今天已经过去的时间。保存后应立即补发；点「完成」后重启应用，不应再出现。
3. 新建未来一分钟的计划。退出应用，等过了该时间再启动，当天应补提醒。跨天不追发旧计划。
4. 待确认、待补充信息与个人计划可以选择「10 分钟后」。Codex / DSH 的「本轮结束」通知自动进入记录，不计入待处理，也没有「标为已处理」按钮；仍通知一次并可打开原任务。中断等其他状态仍可手动标记处理。关闭待确认（没有 MIRA 代答 token）或个人计划弹窗会保留待处理事项；关闭带 token 的 DSH 审批弹窗会立即交还 DSH 原生对话框。
5. 「连接与设置」→「配置本机连接」。原有 hooks 会保留并备份。然后在 Codex 的 hooks 审核界面审查并信任接收器，启动新会话。CLI 可用 `/hooks` 进行审核。不要绕过 hook 信任。
6. 在新的本地 Codex 会话中完成一轮真实任务。MIRA 应收到「本轮结束」，点击进入原会话。权限请求需用你实际需要审批的任务验收，MIRA 不会自动批准。
7. 在设置启用「登录电脑时启动 MIRA」。macOS 可能要求在系统设置的登录项中允许；以系统最终状态为准。注册前请把 app 放在固定位置。
8. DSH 连接：先启动一次 DeepSeek Harness，再运行 `bash scripts/install-dsh-bridge.sh`。在 DSH 里跑完一轮（或让它报错结束），MIRA 应出现「本轮结束」或「任务失败」。若没有，退出并重新打开 DSH 后再试；`dsh://open` 只会把 DSH 窗口切到前台，不会精确跳到某个会话。
9. DSH 审批：让 DSH 执行一个需要确认的操作，MIRA 弹窗会出现「允许一次 / 拒绝 / 去 DSH 处理」。允许或拒绝后弹窗自动收起；不操作则约 60 秒后回落到 DSH 原生对话框，关闭 MIRA 审批弹窗也会立即回落。
10. 连接版本与记录整理：设置页的 Codex / DSH 卡片应显示「接收器 0.4.0 / 插件 0.4.0」。若显示「旧版」或「→ 需要 0.4.0」，点对应更新按钮，再重启 DSH 或新开一个 Codex 会话：状态先变为「已更新到 0.4.0 · 重启后生效」，收到新事件后变为「最近事件」。「记录与存储」显示记录与去重键数量，点「立即整理」应给出保留或导出条数；有导出时数据目录出现 `records-YYYY-MM.md`。
11. UniCourse：设置页「UniCourse 课程更新」→「登录 UniCourse」，完成学校登录后窗口自动关闭，状态应显示「N 门课 · M 个未提交 · 上次 …」。任务库「课程」只出现未提交的作业，且带截止时间；再点「立即同步」不应重复生成。在网页上提交一个作业后同步，对应任务应自动变成已完成。关闭「新作业写入任务库」后，同步不再新建任务。Cookie 失效时状态显示「登录已过期」，重新登录后恢复。
12. 学习通：设置页「学习通作业」→「登录 学习通」，完成登录后状态应显示「N 门课 · M 个待做」。任务库「课程」出现待做作业/考试（列表带截止时间的会写入日期），再同步不重复；在网页完成一个作业后同步，任务从任务库移除。若状态显示「0 个待做」但页面确实有作业，数据目录的 `chaoxing-worklist-sample.html` 就是校准样本（不含 Cookie）。
13. 666 教学系统：设置页「RUC 教学系统（666）」→「登录 教学系统」，登录后状态应显示「N 门课 · M 场待考」。任务库「课程」出现未结束的考试，结束时间正确；再同步不重复；考试结束后同步会归档并保留历史。若显示「没有读到课程列表」或「0 场待考」但页面有考试，数据目录的 `teaching-sample.txt` 是 action 的原始返回，可用于对齐字段。
14. 网页监控：在「监控」页点「添加网址」，输入一个可访问的课程/作业页，需要登录时在内置浏览器里完成登录；等待页面自动扫描（或点「扫描此页」），应出现候选列表和条目预览。保存后任务库出现当前条目，且不补发旧通知；网页上新增一条后点「立即检查」，应生成一条「新条目」提醒和对应任务；把条目改成「已提交」再检查，任务应自动完成；仅从列表移除时不得自动完成。伪装成登录页时状态应提示重新登录，而不是把登录页当列表。

## 真实连接范围

- 接收官方 `Stop`、`PermissionRequest`、`UserPromptSubmit`、`Interrupt` hooks。
- `PermissionRequest` 触发后台状态核对。MIRA 只在 Codex 会话有待人工处理的工具审批时弹窗。后台连接不可用时，工具审批由 Codex 原会话提示。
- `Stop` 表示轮次结束，**不保证整个目标完成或成功**；目前不能可靠区分任务失败。
- `PreToolUse` 对 `request_user_input` 的支持取决于客户端工具覆盖；尚未完成桌面端真实补充信息事件验证。
- hook 只输出 `{}`，不返回批准、拒绝、继续或阻断决定。
- `codex://threads/<session_id>` 在当前安装客户端资源中可确认；是客户端依赖的跳转路径，后续客户端版本可能变化。提供复制标识兜底。
- DSH 走桌面 profile 的第三方插件：把 `turn/end` 的 reason 映射成本轮结束、任务失败、已中断、已拦截、已达上限；审批在 MIRA 存活且有心跳时由弹窗代答（一次性 token、60 秒过期），否则直接回落到 DSH 原生对话框。不修改会话内容。
- DSH 的深链目前只有 `dsh://open`（聚焦主窗口）；弹窗保留会话标题和短标识作为定位兜底。插件只挂载在桌面 profile，`dsh web` / `headless` 不生效。
- 本地用户层 hooks 不能监控个人账号已有云端任务或普通 ChatGPT 对话。桌面计划通过独立文件适配器同步，ChatGPT 云端 Tasks 尚未连接；也可在 MIRA 新建个人计划并粘贴对话链接。
- **配置成功不等于已连通。** 界面直到收到真实 hook 文件才显示最近事件时间。信任审核必须由用户在 Codex 中完成；应用不修改信任记录。
- 事件名称优先取本机 `UserPromptSubmit` 的提示词首段；接收器只把首段（≤160 字符）交给 SDK，由 MIRA 清洗并裁成 44 字，缓存在数据目录的 `title-cache.json`，供本轮后续 Stop / Interrupt / 审批事件复用。读不到提示词时回退为本地 Codex 元数据里的可见会话名，再退回项目名与会话短标识。只读查询匹配的会话，不读完整对话、浏览器 Cookie、凭据或完整命令。此适配依赖客户端内部 SQLite 格式，后续版本可能变化。
- UniCourse 读取首页课程列表与每门课的作业页（服务端渲染的 `.panel`），只取未提交作业与截止时间；公告读取 `morenews` JSON。不读课程详情与附件、不调用未公开接口；解析不到时留诊断片段，页面改版需要重新校准 `Sources/UniCourse.swift` 里的选择规则。
- 学习通读取 `backclazzdata` 与课程级 `workList` / `examList` H5 页面，只取标题、状态、链接和页面上可见的截止时间；不调用需要客户端签名的 `gas/taskmsg`，不读作业详情。
- 网页监控用 MIRA 内置的 WKWebView 读取用户选定的页面；识别是本地 DOM 启发式，不调用模型、不上传正文。登录态由 WebKit 数据仓库保管，配置只写 `web-watches.json`（0600），不保存 Cookie 或密码。
- 666 教学系统通过 Auth.js 会话 Cookie 调用 `listMyCourses` / `listMyExam` 两个 Server Action，只取未结束考试的标题、课程与结束时间；不渲染页面、不进考场、不读试卷内容。

## 存储与行为

`~/Library/Application Support/MIRA/state.json` 保存计划、记录、去重键与任务库，原子写入。网页监控的配置单独放在同目录 `web-watches.json`（0600），不写进 `state.json`；登录态在 WebKit 自己的数据仓库里。任务库使用 `schemaVersion: 2` 的版本化本地状态迁移：旧状态缺少 `tasks` / `taskCategories` 时会在启动时补齐默认分类并写回，原有计划与记录不变。`inbox/` 为 hook 原子投递队列；无法解析或链接非法的事件会移入 `inbox/rejected/` 保留原件，不会阻塞后续事件，也不再每 3 秒重复报错。收件箱在运行中被删除时会以 0700 重建；无法列出时会显示错误，而不是静默停止接收。无需 SQLite 即可完成单进程初版；只允许一个应用进程运行。接收器可在应用关闭时写队列，下次启动接收。超过 24 小时的 AI 事件仅归档。每天的计划按本机当前时区、日历日生成一次；有效期到当天午夜。计划编辑影响后续生成，已生成的当天记录保留原内容。

Codex 的「已处理」只关闭 MIRA 提醒，不代表权限已经批准；DSH 的「允许一次 / 拒绝」会把 `allowed-once` / `rejected` 真实回传给当前请求。运行状态来自最近 hook，不是持续心跳；客户端崩溃后可能仍显示运行中。不会在通知中执行模型请求。

适配器只把提示词首段（最多 160 字符）交给 MIRA，MIRA 统一清洗并裁成 44 字（头 28 + 尾 12），不保存完整提示词；本轮标题缓存在 `title-cache.json`（0600、24 小时过期），供后续事件复用。旧版接收器自己的 `titles/` 目录不再写入，7 天后由整理流程清理。提醒标题在展示时会去掉 Markdown 标题/列表前缀和「任务：」标签，`state.json` 中的原文不会被改写。MIRA 每 3 秒写一次 `heartbeat`；DSH 只有在心跳新鲜（15 秒内）时才把审批交给弹窗。审批回执写在 `decisions/`（0700 目录、0600 文件、一次性读取），同一用户的其他进程理论上可以伪造回执——这是本地确认机制的边界。收件箱条目支持可选 `dismiss` 字段：值为另一条提醒的 id 时，只关闭那条提醒并丢弃自身，用于审批决定或提问回答后的自动收起。记录与 `seen` 由保留策略控制：超过 90 天或超过 500 条的最旧已处理记录，先按月份导出到 `records-YYYY-MM.md` 再从 `state.json` 移除；待处理项不参与清理。系统勿扰可能抑制系统通知，可在任务中心查看保留记录。浮动提醒一次只显示一条，批量事件仍全部进入收件箱。

## 编译与测试

```sh
bash scripts/build.sh
python3 -m unittest discover -s tests -p 'test_*.py'
node --test tests/test_dsh_bridge.mjs
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift Sources/TaskCore.swift Sources/AdapterContract.swift tests/CoreTests.swift -o /tmp/mira-core-tests
/tmp/mira-core-tests
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift Sources/TaskCore.swift Sources/AdapterContract.swift Sources/ScheduledTasks.swift tests/ScheduledTasksTests.swift -o /tmp/mira-schedules-tests
/tmp/mira-schedules-tests
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift Sources/TaskCore.swift Sources/AdapterContract.swift tests/TaskLibraryTests.swift -o /tmp/mira-task-tests
/tmp/mira-task-tests
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift Sources/TaskCore.swift Sources/AdapterContract.swift Sources/WebCookie.swift Sources/SyncInterval.swift Sources/UniCourse.swift tests/UniCourseTests.swift -o /tmp/mira-unicourse-tests
/tmp/mira-unicourse-tests
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift Sources/TaskCore.swift Sources/AdapterContract.swift Sources/WebCookie.swift Sources/SyncInterval.swift Sources/Chaoxing.swift tests/ChaoxingTests.swift -o /tmp/mira-chaoxing-tests
/tmp/mira-chaoxing-tests
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift Sources/TaskCore.swift Sources/AdapterContract.swift Sources/WebCookie.swift Sources/SyncInterval.swift Sources/TeachingSystem.swift tests/TeachingSystemTests.swift -o /tmp/mira-teach-tests
/tmp/mira-teach-tests
swiftc -module-cache-path /tmp/mira-swift-cache Sources/Core.swift Sources/TaskCore.swift Sources/AdapterContract.swift Sources/SyncInterval.swift Sources/WebWatch.swift tests/WebWatchTests.swift -o /tmp/mira-webwatch-tests
/tmp/mira-webwatch-tests
open dist/MIRA.app
```

依赖 Apple Command Line Tools（Swift）与系统 `/usr/bin/python3`（hook）。`scripts/build.sh` 默认以 `$(uname -m)-apple-macos13.0` 为目标，并校验产物 `minos` 与 `Info.plist` 声明的 macOS 13 一致；可用 `MIRA_TARGET` 覆盖。构建仅做本机 ad-hoc 签名，未公证，不应将此二进制作为正式公开发行版。

## 移除连接

退出 MIRA 并先在设置关闭登录启动。从 `~/.codex/hooks.json` 中仅删除 command 包含 `MIRA/receive.py` 的 hook 项，保留其他配置；安装前备份位于同一目录 `hooks.mira-backup-*.json`。DSH 连接用 `bash scripts/uninstall-dsh-bridge.sh` 移除插件目录与补丁行，补丁备份在同目录 `cordis.patch.yml.mira-backup-*`。删除 app 即可卸载，数据目录可留存。

## 依据

- [官方 Hooks 事件、信任与执行语义](https://learn.chatgpt.com/docs/hooks)
- [官方桌面插件生命周期 hooks](https://developers.openai.com/plugins/build/plugins)

## Codex 后台确认

MIRA 运行时通过当前用户的 Codex IPC 订阅会话状态。计划确认可在弹窗展开全文，点击「执行计划」后台提交；「稍后」保留请求。提交前重新读取请求和模型设置，内容变化时要求重新确认，超时提交不会自动重发。连接状态显示在设置页。

内部协议适配在 `integrations/codex/bridge.py`，以当前桌面客户端版本为目标。真实回传验证结果保存在数据目录的 `codex-verified.json`，绑定客户端构建信息，升级后需重新验证。当前已真实验证计划执行；命令、文件和访问权限类型只有模拟测试，按钮保持禁用，需出现真实人工审批完成验证后启用。断线或未验证时仍可打开原会话处理。待确认正文仅保留在辅助进程与界面内存，提交日志只保存请求标识、动作和结果状态。

验证命令：`python3 -m unittest discover -s tests -p 'test_codex_bridge.py'`。
