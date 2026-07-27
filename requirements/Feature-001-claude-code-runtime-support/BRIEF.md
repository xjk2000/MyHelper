# Feature-001: 多 Agent Runtime 统计架构与 Claude Code 支持

| 项         | 值         |
| ---------- | ---------- |
| Phase      | dev        |
| 优先级     | P0         |
| 负责人     | <待填>     |
| 目标日期   | <待填>     |
| 涉及子系统 | Sources/CodexUsageWidget, docs, Resources |

## 一句话描述

将 codexU 从单一 Codex 用量小组件升级为可接入 Codex、Claude Code 等多 Agent Runtime 的本地统计框架。

## 背景

当前 codexU 的读取、聚合、定价、任务看板和 UI 命名都围绕 Codex 单一 Runtime 展开。新增 Claude Code 支持时，如果继续在同一套 `CodexUsageReader` 和 SwiftUI 视图中追加条件分支，会快速形成耦合：数据源路径、账户额度语义、token 结构、任务模型、工具/Skill 归因和错误提示都会互相影响。

Claude Code 本地也具备用量统计基础：`~/.claude/projects/**/*.jsonl` 保存会话 transcript 和 per-message usage，`~/.claude/stats-cache.json` 保存 `/usage` 聚合缓存，`statusLine` 可暴露 active session 的 context、cost、rate limit、worktree 和 PR 信息。它与 Codex 的差异在于：没有等价的后台 `app-server account/*` 接口，额度数据更适合通过 active session 快照桥接；但在工具、Skill、Subagent、Plugin、MCP、文件变更和任务维度上拥有更丰富的本地事件。

本 Feature 需要先重构代码架构，把 Agent Runtime 的采集、标准化、聚合和 UI 展示边界拆清楚，确保 Codex 与 Claude Code 独立演进，同时可以在总览层做跨 Runtime 汇总。

## 关键决策

- 采用多 Runtime Provider 架构：Codex 与 Claude Code 各自实现独立 reader/parser，不共享私有数据结构。
- 引入统一的 Agent Usage 领域模型：UI 面向标准化快照，不直接依赖 `CodexUsageReader` 或 Claude 本地文件格式。
- 聚合层只处理标准化结果，不能回读 provider 私有文件或拼接 provider 专属字段。
- Claude Code 额度分两档支持：历史统计直接解析本地 JSONL；active rate limit/context/cost 通过 statusLine 快照缓存桥接，缺失时明确显示不可用。
- 保持隐私边界：不上传 usage、线程、路径、prompt、tool arguments 或 raw logs；本地解析默认只读取结构化字段和 token/cost 元数据。

## 上下文索引

- 原始素材见 [context/_INDEX.md](context/_INDEX.md)
