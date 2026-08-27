# pi-agents-meeting-discuss 开发指南

> 本文件指导 **本项目本身的开发**。与 `templates/AGENTS.md.tpl`（运行时参与讨论
> 的 LLM 行为指令）是两回事。

## 项目目的

实现并维护 **Pi 版 Meeting 模式多 agent 文件式讨论协议**，与 opencode 版保持
协议/状态机/测试同构，只替换 LLM 运行时。

## 架构

```
meeting_core.py      纯逻辑判定——无 I/O
meeting_fs.py        git/文件层
meeting_engine.py    【唯一状态机】+ 协议信号 + responder 注入
meeting_loop.py      Pi 薄壳：responder = wake_llm（真实 LLM）
fake_agent.py        测试薄壳：responder = 随机决策
start_discussion.py  环境生成/启动/清理
templates/           AGENTS.md.tpl / agent.md.tpl / gitignore.tpl / spec-readme.md.tpl
```

**核心不变式**：状态机只在 `meeting_engine.agent_loop` 一份；fake_agent 与
meeting_loop 通过注入 responder 复用。

## 设计原则

沿用 `agents-meeting-discuss/AGENTS.md` 的全部原则：

1. 确定性归 loop，LLM 只提供内容。
2. 状态从 git 共享事实推导（bare 树，每 agent 目录内序号最大）。
3. 每个动作有显式前提。
4. mode 判定 = 聚合所有 agent 最后一条。
5. 单向状态流：meeting → af → RR → result。
6. 状态变量定义清晰（is_first / read_point / speak_rounds）。
7. 无静默铁律：无产出重试 + loop 代写。
8. 测试找逻辑漏洞，不堆补丁。
9. 复杂度匹配设计。
10. bug→根因→决策规则。
11. 新概念禁令。
12. wake-logs 必须保留。
13. 协议/环境属性单一事实源 = protocol.json。
14. 内容分层：共享协议/背景 → AGENTS.md；per-agent 身份/分工 → `.pi/agent/*.md`
    + `pi-agent.json`；讨论起点 → question.md。
15. 审核驱动的三类缺陷模式：异常兜底、测试对象=生产对象、单一事实源不被 CLI 覆盖。

## Pi 适配注意事项

- `pi` 没有 `--dir`：`subprocess.run(..., cwd=workdir)` 是必须的。
- `pi` 没有 opencode agent 定义：身份用 `--append-system-prompt` 注入，
  模型/思考档位用 `pi-agent.json` 里的 `--model` / `--thinking`。
- session 必须放在 `<base>/pi-sessions/`：保证 `--cleanup` 一次删除、不留全局残留。
- `--mode json` 首行是 SessionHeader，可从 `{"type":"session","id":...}` 读取 sessionID。

## Git 准则（用户约定，2026-08-19）

1. **每次改动先更新本地 git**：对本项目代码/文档的每次修改，先 `git add` + `git commit` 记录。
2. **阶段性完成即推送**：完成一个阶段性修改后（例如新增文档、完成一批修复、跑通一次验证），
   必须同时 `git push origin main` 推送到 GitHub。
3. **本地与远程保持同步**：提交后确认工作区干净、远程与本地 HEAD 一致。
4. **提交信息**：使用清晰、描述性的 message，说明本次改动内容。
5. **skill 设计文档同步**：对 `pi-meeting` skill 的任何修改（wrapper、SKILL.md、npm 结构、流程、默认参数等），必须同步更新 `docs/pi-meeting-skill-design.md`。
