# Claude Code 本地统计调研摘要

收集日期：2026-07-07

## 本机验证结果

- Claude Code 可执行文件：`claude`
- 本机版本：`2.1.161`
- 本机会话目录：`~/.claude/projects/**`
- 本机 JSONL 会话数：约 130 个 JSONL 文件
- assistant message usage 字段包含：
  - `input_tokens`
  - `cache_creation_input_tokens`
  - `cache_read_input_tokens`
  - `output_tokens`
  - `server_tool_use`
  - `service_tier`
  - `cache_creation`
- top-level 事件字段包含：
  - `cwd`
  - `gitBranch`
  - `sessionId`
  - `timestamp`
  - `type`
  - `uuid`
  - `message`
  - `toolUseResult`
  - `attributionSkill`
  - `attributionMcpServer`
  - `attributionMcpTool`
  - `agentId`
  - `agentName`

## 官方文档确认

- Claude Code `~/.claude/projects/<project>/<session>.jsonl` 保存完整 conversation transcript，默认清理周期为 30 天。
- `~/.claude/stats-cache.json` 保存 `/usage` 展示的聚合 token 和 cost 统计。
- `statusLine` 命令通过 stdin 收到 JSON，可包含 `cost`、`context_window`、`rate_limits`、`workspace`、`pr`、`worktree`、`agent` 等字段。
- `rate_limits.five_hour` 与 `rate_limits.seven_day` 提供 `used_percentage` 和 `resets_at`，但字段可能在首次 API 响应前缺失，且仅对 Claude.ai 订阅用户有效。
- OpenTelemetry 指标支持 `claude_code.token.usage`、`claude_code.cost.usage`、session、lines of code、PR、commit、tool decision 等维度。

## 对 codexU 的影响

### 可复刻 Codex 能力

- 今日、近 7 天、累计 token。
- cached input、cache creation input、uncached input、output 拆分。
- API 等效价值估算。
- 用量热力图和趋势摘要。
- 项目排行。
- 工具 TOP 和 Skill TOP。
- 本地任务看板的部分能力。

### 不能完全复刻 Codex 能力

- 后台直接查询账户额度：Claude Code 没有发现与 Codex `app-server account/rateLimits/read` 等价的稳定本地 API。
- Codex automation 看板：Claude Code 没有 `~/.codex/automations/**/automation.toml` 等价标准数据源。
- Cloud lifetime token 官方口径：Claude 本地历史是本机近 30 天 transcript 和 stats-cache，不代表跨设备或 Claude.ai 全局权威账单。

### Claude Code 可额外提供的能力

- 当前 context window 使用率和剩余比例。
- 当前 session cost、API duration、wall duration。
- lines added / removed。
- Subagent、background agent、plugin、MCP server/tool 归因。
- TaskCreate/TaskUpdate 结构化任务。
- file-history/checkpoint 维度。
- PR、worktree、repo 元数据。

## 设计约束

- 不能读取或展示 prompt、assistant 正文、tool arguments、tool output 正文。
- JSONL parser 默认只抽取结构化 usage、metadata 和 tool 名称。
- 所有 Claude Code 历史统计必须标注为本机估算。
- 额度数据缺失时显示不可用，不能用 0 伪装。
