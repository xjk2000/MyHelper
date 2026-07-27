# Feature-001 PRD: 多 Agent Runtime 统计架构与 Claude Code 支持

版本：V1.0<br>
日期：2026-07-07<br>
作者：Codex<br>
状态：Draft

## 1. 需求概述

### 1.1 背景

codexU 当前定位是本地 macOS 桌面小组件，用于查看 Codex 额度、token 用量、趋势、项目排行、工具和 Skill 使用。现有实现已经能满足单一 Codex Runtime，但数据模型、读取器、聚合逻辑和 UI 文案都以 Codex 为中心。

新增 Claude Code 支持会引入不同的数据语义：Claude Code 的历史 token 来自 `~/.claude/projects/**/*.jsonl`，聚合缓存来自 `~/.claude/stats-cache.json`，active session 的额度、context、cost 和 worktree/PR 信息来自 `statusLine` JSON。它没有与 Codex `app-server account/rateLimits/read` 完全等价的后台账户接口，但拥有更丰富的 Subagent、Plugin、MCP、Task 和 file-history 维度。

因此本 Feature 不应只做“复制一个 ClaudeUsageReader”，而应先把 codexU 重构为多 Agent Runtime 架构：各 Runtime 独立采集和降级，统一输出标准化快照，并在 UI 和 JSON dump 层支持单 Runtime 和跨 Runtime 聚合。

### 1.2 产品目标

- 支持 Codex 与 Claude Code 两类 Agent Runtime 的本地统计。
- 保持各 Runtime 数据源和解析逻辑互相独立，避免 provider 专属字段泄漏到公共 UI。
- 提供跨 Runtime 总览：总 token、本月 API 等效价值、最近 7 日趋势、项目排行、工具/Skill 结构。
- Claude Code 首版至少支持本地历史用量、趋势、项目排行、工具/Skill TOP 和任务看板基础能力。
- 对 Claude Code 无法后台读取的额度数据明确降级，不伪造成 0 或沿用 Codex 文案。
- 为后续接入 Cursor、Gemini CLI、Aider 等 Runtime 保留扩展点。

### 1.3 用户角色与场景

| 角色 | 场景 | 期望 |
| --- | --- | --- |
| 多 Agent Runtime 用户 | 同时使用 Codex 和 Claude Code 做开发 | 一个小组件看到两边的本地用量和趋势 |
| 订阅型用户 | 关注不同工具订阅价值 | 分别看到 Codex 与 Claude Code 的 API 等效价值估算 |
| 工具型开发者 | 想复盘工具调用结构 | 对比 Codex 工具、Claude Code Bash/Read/Edit/Agent/MCP 使用情况 |
| 隐私敏感用户 | 不希望桌面暴露会话内容 | 只展示聚合指标、路径尾名、结构化任务和口径说明 |
| 后续维护者 | 需要继续接入新 Runtime | 不需要修改 Codex 或 Claude 解析器即可新增 Provider |

## 2. 范围

### 2.1 In Scope

- 重构 Swift 代码结构，从单文件单 reader 演进为多文件、多 Runtime Provider 架构。
- 新增公共领域模型，用于表达 Runtime、账户/额度、token、趋势、项目、工具、Skill、任务、诊断信息。
- 新增 Codex provider，把现有 Codex 读取和解析逻辑迁移到 provider 内。
- 新增 Claude Code provider，读取：
  - `~/.claude/projects/**/*.jsonl`
  - `~/.claude/stats-cache.json`
  - `~/.claude/tasks/**`
  - `~/.claude.json`
  - 可选 statusLine snapshot cache
- 新增跨 Runtime aggregator，支持总览聚合和 provider 级分组。
- 更新 UI 信息架构，支持 Runtime 切换和 All Runtime 汇总。
- 新增状态栏菜单：点击状态栏图标先展示 Codex 与 Claude Code 的独立卡片，每张卡片显示 5 小时剩余、7 日剩余和今日 token。
- 新增状态栏卡片点击入口：点击 Codex 卡片打开主界面并默认展示 Codex；点击 Claude Code 卡片打开主界面并默认展示 Claude Code。
- 主界面新增顶部全局 Runtime 开关，用于在 Codex 与 Claude Code 之间手动切换。
- 更新 `--dump-json` 输出结构，兼容旧字段并新增 runtime 维度。
- 更新 README、README.en、SECURITY 和 RESEARCH 中的数据源说明。
- 调整 Makefile，使 `Sources/CodexUsageWidget/**/*.swift` 都参与编译。

### 2.2 Out of Scope

- 不上传任何 usage、thread、transcript、路径、日志或账户数据。
- 不读取 Claude Code prompt 正文、assistant 回复正文、tool arguments 或 tool output 正文。
- 不自动修改用户的 Claude Code 设置，除非后续独立需求确认 statusLine bridge 安装方案。
- 不承诺 Claude Code 跨设备、Claude.ai 全局或官方账单口径。
- 不实现 Cursor、Gemini CLI、Aider 等第三方 Runtime，仅保留扩展接口。
- 不在本 Feature 内重新设计视觉系统或改名产品。

## 3. 功能需求

### F1. Runtime Provider 架构

优先级：P0

系统必须支持多个 Runtime Provider。每个 Provider 独立负责：

- 发现本机数据源。
- 读取和解析 provider 专属文件/API。
- 输出标准化 `AgentRuntimeSnapshot`。
- 返回诊断信息和数据质量标记。
- 自行管理 cache 和 fingerprint。

验收标准：

- Codex 与 Claude Code provider 可以单独启用、禁用和失败。
- 某个 provider 读取失败不影响其他 provider 展示。
- 公共 UI 不直接读取 `~/.codex` 或 `~/.claude`。

### F2. 标准化用量模型

优先级：P0

标准化模型必须覆盖：

- Runtime identity：id、displayName、kind、isAvailable。
- Account/quota：账户类型、额度窗口、重置时间、数据来源。
- Token usage：input、uncached input、cache creation、cache read、cached input、output、reasoning output、visible total。
- Cost/value：按 provider 价格表估算 API 等效价值。
- Trends：日桶、热力图、最近 7 日摘要、月累计。
- Projects：项目名、路径、tokens、估算价值、线程/会话数、最近活跃。
- Tools：工具名、分类、调用次数、估算 token、估算价值。
- Skills：Skill 名、来源、加载次数、线程/会话数、静态 token 估算。
- Tasks：任务列、任务项、状态、最近更新时间。
- Diagnostics：缺失数据源、权限、解析失败、降级口径。

验收标准：

- Codex provider 迁移后 UI 指标与迁移前保持一致。
- Claude Code provider 输出同一套模型，缺失额度时只影响额度字段。

### F3. Claude Code 历史用量统计

优先级：P0

读取 `~/.claude/projects/**/*.jsonl` 中 assistant message 的 `message.usage` 字段，聚合：

- 今日 token。
- 最近 7 日 token。
- 本月 token 和 API 等效价值。
- 累计本机 token。
- cache creation、cache read、input、output 拆分。
- 按模型分组的 token 与估算价值。

验收标准：

- JSONL 中重复 message 不重复计入。
- 无法识别价格的模型仍展示 token，估算价值显示不可用。
- 解析过程不读取或保留正文内容。

### F4. Claude Code 趋势、项目、工具和 Skill 分析

优先级：P0

基于 Claude Code JSONL 和本地状态聚合：

- 最近半年 token 热力图。
- 最近 7 日趋势摘要。
- 项目排行：从项目目录编码、`cwd` 或 `~/.claude.json.projects` 归因。
- 工具 TOP：从 `tool_use.name` 计数。
- Skill TOP：从 `Skill` tool、`attributionSkill`、`~/.claude.json.skillUsage` 归因。

验收标准：

- 项目名默认只展示路径尾名。
- 工具和 Skill 不展示参数。
- 工具 token 归因使用估算文案。

### F5. Claude Code 任务看板

优先级：P1

读取 `~/.claude/tasks/<session>/*.json`，生成 Claude Code 任务看板：

- `in_progress` -> 进行中。
- `pending` -> 待处理。
- `completed` -> 完成。
- 其他状态归入待处理并标注原状态。

验收标准：

- 任务标题使用 `subject`，描述只作为内部摘要，不在首屏暴露长正文。
- 任务按更新时间或文件修改时间排序。

### F6. Claude Code active snapshot bridge

优先级：P1

支持读取一个本地 statusLine snapshot cache 文件，用于补充 active session：

- 5 小时/7 天额度 used percentage 和 reset time。
- context window used/remaining percentage。
- current session cost、duration、API duration。
- lines added/removed。
- workspace、git branch、PR、worktree。

验收标准：

- 没有 snapshot cache 时 UI 显示“需要 Claude Code active session 快照”，不报错。
- snapshot 过期时显示 stale 状态。
- 首版只读取 cache，不自动安装 statusLine。

### F7. UI Runtime 切换与聚合

优先级：P0

UI 需要支持：

- Codex：Codex 详情。
- Claude Code：Claude Code 详情。

展示规则：

- 主界面顶部提供全局 segmented control：`Codex` / `Claude Code`。
- 点击 segmented control 只切换当前 snapshot 的展示范围，不触发重新读取。
- 刷新后保持当前 Runtime 选择。
- Runtime 详情视图展示 provider 专属诊断和可用能力。
- All 聚合只用于状态栏今日总 token 和后续可选总览，不作为主界面首版默认 Runtime。

验收标准：

- Codex 单 Runtime 使用体验不退化。
- Claude Code 额度缺失不影响 token 和趋势展示。
- 点击主界面顶部开关后，额度、今日 token、趋势、项目、工具、Skill、任务面板同步切换。

### F8. 状态栏菜单与 Runtime 快速入口

优先级：P0

点击 macOS 状态栏里的 codexU 图标后，不直接打开主窗口，而是先展示一个状态栏菜单。菜单中包含：

- Codex 独立卡片。
- Claude Code 独立卡片。
- 今日总 token 汇总行。
- 刷新、打开主界面、退出等基础操作。

每张 Runtime 卡片必须展示：

- 5 小时剩余用量。
- 7 日剩余用量。
- 今日 token 用量。
- 数据状态 chip，例如 `Available`、`Local only`、`Snapshot needed`、`Stale`、`Unavailable`。

点击行为：

- 点击 Codex 卡片：打开当前主界面，将顶部 Runtime 开关切到 Codex。
- 点击 Claude Code 卡片：打开当前主界面，将顶部 Runtime 开关切到 Claude Code。
- 点击菜单中的“打开主界面”：按当前已选择 Runtime 打开主界面；没有选择时按默认选择规则。

降级规则：

- Codex 额度不可用时，5 小时/7 日显示 `--`，今日 token 仍可显示。
- Claude Code 没有 active statusLine snapshot 时，5 小时/7 日显示 `--`，卡片状态为 `Snapshot needed`。
- Claude Code snapshot 超过 15 分钟时，卡片状态为 `Stale`。
- 两个 Runtime 的今日 token 可以合并展示为“今日总 token”；额度百分比不可合并。

验收标准：

- 状态栏菜单同时展示 Codex 和 Claude Code 两张卡片。
- 每张卡片点击后打开主界面并默认显示对应 Runtime。
- 状态栏菜单不展示 prompt、assistant 回复、tool arguments、tool output 或完整路径。
- 菜单刷新后不改变用户已选择的主界面 Runtime。

### F9. JSON dump 与文档

优先级：P0

`--dump-json` 需要新增 runtime-aware 结构，同时保留旧字段一段时间用于兼容。

验收标准：

- JSON 包含 `runtimes[]` 和 `aggregate`。
- 原有 Codex 字段仍可输出，直到后续版本明确移除。
- README 和 SECURITY 明确列出新增 Claude Code 本地数据源。

## 4. UI 与交互设计

详细 UI 与交互设计见 [UI_INTERACTION_DESIGN.md](UI_INTERACTION_DESIGN.md)。

### 4.1 状态栏菜单

状态栏菜单是本 Feature 的快速入口。点击状态栏图标后，展示轻量菜单而不是直接打开主窗口。菜单以 Runtime 卡片为核心，Codex 和 Claude Code 分别一张卡片，避免混合展示不同额度口径。

菜单信息层级：

1. Header：codexU、最后刷新时间、刷新按钮。
2. Runtime 卡片：Codex、Claude Code。
3. 今日总 token：Codex + Claude Code 的本机 token 合计。
4. Footer：打开主界面、退出。

Runtime 卡片字段：

| 字段 | 说明 |
| --- | --- |
| Runtime 名称 | `Codex` / `Claude Code` |
| 状态 chip | Available / Local only / Snapshot needed / Stale / Unavailable |
| 5 小时剩余 | 剩余百分比和 reset time；不可用显示 `--` |
| 7 日剩余 | 剩余百分比和 reset time；不可用显示 `--` |
| 今日 token | 当前 Runtime 今日本机 token |
| 数据口径 | 官方额度 + 本机统计 / active snapshot + 本机统计 |

### 4.2 主界面 Runtime 切换

主界面顶部新增全局 Runtime 开关：

```text
[ Codex | Claude Code ]
```

默认选择规则：

- 第一次启动默认 Codex。
- 如果本机没有 Codex 数据但有 Claude Code 数据，默认 Claude Code。
- 如果用户从状态栏菜单点击 Runtime 卡片打开主界面，以点击的 Runtime 为准。
- 用户在主界面手动切换后，当前进程内保持选择。

### 4.3 点击路径

- 状态栏图标点击：展示状态栏菜单。
- 状态栏 Codex 卡片点击：打开主界面并展示 Codex。
- 状态栏 Claude Code 卡片点击：打开主界面并展示 Claude Code。
- 主界面 Runtime 开关点击：切换所有主面板的数据范围。

## 5. 非功能需求

### 5.1 隐私

- 不上传任何数据。
- 不读取认证 token 值。
- 不展示 prompt、assistant 正文、tool arguments、tool result 正文。
- JSONL parser 只抽取 timestamp、usage、model、cwd、tool name、attribution metadata、session id 等结构化字段。

### 5.2 可靠性

- provider 失败互不影响。
- 文件不存在、JSON 行损坏、字段缺失、权限不足均进入 diagnostics。
- 缺失值不能伪造为 0。
- cache fingerprint 必须包含文件大小和修改时间。

### 5.3 性能

- 默认刷新不能全量重复解析大型 JSONL。
- 单次刷新目标：常规本机数据量下小于 2 秒。
- provider 解析应支持 grep/streaming 快速路径和持久化 cache。

### 5.4 可维护性

- 单个 Swift 文件建议不超过 800 行；超出需拆分。
- Provider 私有 parser 不得依赖 SwiftUI 类型。
- UI 不得依赖 provider 私有路径或 JSON key。
- 新增 Runtime 只需要实现协议并注册，不修改现有 provider。

## 6. 数据源

| Runtime | 数据源 | 用途 | 风险 |
| --- | --- | --- | --- |
| Codex | `codex app-server` | 账户、额度、cloud lifetime token | 接口不可用时降级 |
| Codex | `~/.codex/state_5.sqlite` | 线程、tokens、项目、任务 | SQLite schema 变化 |
| Codex | `~/.codex/sessions/**/*.jsonl` | 精细 token、工具、Skill | 大文件性能 |
| Codex | `~/.codex/automations/**/*.toml` | 定时任务 | 格式变化 |
| Claude Code | `~/.claude/projects/**/*.jsonl` | 历史 token、工具、Skill、项目 | 明文 transcript，必须只抽结构字段 |
| Claude Code | `~/.claude/stats-cache.json` | `/usage` 聚合缓存辅助 | 可能滞后 |
| Claude Code | `~/.claude/tasks/**/*.json` | 结构化任务 | task schema 变化 |
| Claude Code | `~/.claude.json` | 项目、Skill、last metrics 辅助 | 包含配置与状态，避免读取敏感值 |
| Claude Code | statusLine snapshot cache | active quota/context/cost | 需要用户配置或后续安装桥接 |

## 7. 业务流程

### 7.1 刷新流程

1. UI 触发刷新。
2. Runtime registry 获取启用的 providers。
3. 每个 provider 独立读取本地数据并输出 snapshot。
4. Aggregator 合并可比指标。
5. Store 发布 aggregate 与 runtime snapshots。
6. UI 根据当前 Runtime 选择渲染 All 或详情视图。

### 7.2 Claude Code JSONL 解析流程

1. 枚举 `~/.claude/projects/**/*.jsonl`。
2. 根据 cache fingerprint 判断是否需要解析。
3. streaming 读取 JSONL 行。
4. 只处理 assistant message usage 和 tool_use metadata。
5. 聚合到 session、day、project、tool、skill。
6. 写入 provider cache。

### 7.3 状态栏菜单打开流程

1. 用户点击状态栏图标。
2. App 从 `AgentUsageStore` 读取当前 snapshot。
3. 状态栏菜单渲染 Codex 和 Claude Code 卡片。
4. 用户点击某张 Runtime 卡片。
5. Store 更新 `selectedRuntimeScope`。
6. 主窗口切到前台并展示对应 Runtime。

## 8. 验收标准

- Codex 当前功能在迁移后仍可用：额度、token、趋势、项目、工具、Skill、任务、dump-json。
- Claude Code 历史 token、趋势、项目、工具、Skill 可以从本机数据生成。
- Claude Code 无 active snapshot 时有清晰空状态。
- 状态栏菜单能展示 Codex 与 Claude Code 独立卡片，并显示 5 小时剩余、7 日剩余和今日 token。
- 点击 Codex 或 Claude Code 卡片能打开主界面并默认展示对应 Runtime。
- 主界面顶部 Runtime 开关能在 Codex 与 Claude Code 之间手动切换。
- 今日总 token 能汇总 Codex 与 Claude Code token；额度百分比不做跨 Runtime 合并。
- 任一 provider 数据源缺失时不会导致 app 崩溃。
- 文档明确说明所有 Claude Code 统计均为本机估算，不代表官方账单。

## 9. 开放问题

- 是否在后续版本提供“一键安装 Claude Code statusLine bridge”？
- Claude Code 第三方模型价格表是否内置常见路由模型，还是仅支持用户配置？
- 是否需要新增 Runtime 开关设置，允许用户隐藏某个 provider？
- 状态栏菜单是否需要支持键盘导航和固定展开，作为后续无障碍增强？
