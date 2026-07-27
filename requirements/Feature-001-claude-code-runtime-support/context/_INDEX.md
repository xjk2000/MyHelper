# 素材索引 — Feature-001

| 文件 | 类型 | 关键内容摘要 | 收集日期 |
| ---- | ---- | ------------ | -------- |
| [claude-code-local-research.md](claude-code-local-research.md) | 调研记录 | Claude Code 本地数据源、可复刻功能、限制和新增能力 | 2026-07-07 |
| [../spec/UI_INTERACTION_DESIGN.md](../spec/UI_INTERACTION_DESIGN.md) | UI/交互设计 | 状态栏菜单、Runtime 卡片、主界面全局切换和点击进入行为 | 2026-07-07 |
| [../spec/diagrams/ui-statusbar-menu-runtime-cards.svg](../spec/diagrams/ui-statusbar-menu-runtime-cards.svg) | 效果图 | 状态栏菜单与 Codex/Claude Code Runtime 卡片效果 | 2026-07-07 |
| [../spec/diagrams/ui-main-runtime-switch.svg](../spec/diagrams/ui-main-runtime-switch.svg) | 效果图 | 主界面顶部 Codex/Claude Code 全局切换效果 | 2026-07-07 |

## 关键发现

- Claude Code 本地 JSONL 有 per-message usage，可实现 token、趋势、项目、工具和 Skill 统计。
- Claude Code 没有与 Codex `app-server account/rateLimits/read` 完全等价的后台账户接口；5 小时/7 天额度更适合通过 active session 的 statusLine JSON 获取。
- Claude Code 额外暴露 context window、session cost、lines changed、Subagent、Plugin、MCP、Task、file-history 等 Codex 当前不具备的统计维度。
- 新增 Claude Code 支持前应先引入 Provider/Domain/Aggregator/UI 的分层，避免在单文件单 reader 内继续累积条件分支。

## 开放问题

- Claude Code statusLine 快照桥接是否由 codexU 自动安装，还是只读取用户自行配置的缓存文件？
- 跨 Runtime 汇总默认是否显示路径尾名，还是仅展示脱敏后的项目名？
- Claude Code 第三方模型或路由模型的 API 等效价值是否允许用户配置价格表？
