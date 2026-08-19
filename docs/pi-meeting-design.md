# Pi 版 Meeting 模式设计文档

> 本文档描述 `pi-agents-meeting-discuss` 的**设计与实现**，是 Pi 版自己的项目设计文档。
> 协议原理与状态机继承自 opencode 版 `agents-meeting-discuss`（见上级目录
> `meeting-mode-design.md`）；本文档聚焦本项目如何用 **Pi** 作为 agent 运行时，
> 以及协议如何保持不动、只替换 LLM 适配层与环境生成层。

## 1. 项目定位

一次多 agent 会议式讨论：多个 LLM agent（每个一个独立进程）通过共享 git 仓库
交换消息，讨论一个话题，经过「自由讨论 → 冻结级联 → 轮转收尾」达成共识，
最终由 resultWriter 生成 `result.md`。

**设计原则**：一次讨论 = 一个自包含目录。目录内含 bare 仓库 + 各 agent 工作
clone + 全部配置 + Pi session 文件（`pi-sessions/`），`--cleanup` 一次删除、
不留全局残留。

## 2. 协议原理（与 opencode 版一致）

### 2.1 消息分两类

| 类型 | 本质 | 谁写 | 受发言锁约束 |
|---|---|---|---|
| `message` | 讨论内容 | LLM | ✅ |
| `freezing` | 流程控制（无话可说） | LLM / loop | ❌ |
| `all-freezing` | 流程控制（确认全员冻结） | loop | ❌ |
| `pass` | 流程控制（RR 无异议） | LLM / loop | ❌ |
| `concluded` | 流程控制（收尾） | loop（resultWriter） | ❌ |

### 2.2 五条设计原则

1. 无静默铁律：被唤醒必须产出，失败重试 / loop 代写。
2. 发言锁：写 `freezing` 后不再发 `message`。
3. 配额耗尽 → 确定性 freezing。
4. 状态从 git 共享事实推导（聚合每 agent 最后一条，不依赖时间戳）。
5. 流程控制穿透锁。

### 2.3 状态机

```
meeting（自由发言）→ all-freezing → round-robin（RR）→ result → concluded
```

双配额兜底：`max-meeting`（meeting 发言轮数）、`max-rr`（RR 轮数），保证不僵死。

## 3. 代码分层（状态机只此一份）

| 文件 | 职责 |
|---|---|
| `meeting_core.py` | 纯逻辑判定，无 I/O |
| `meeting_fs.py` | git/文件操作（含 push 并发容错） |
| `meeting_engine.py` | **唯一状态机** + 协议信号 + responder 注入 |
| `meeting_loop.py` | Pi 薄壳：responder = 唤醒 pi |
| `fake_agent.py` | 测试薄壳：responder = 随机决策 |
| `start_discussion.py` | 环境生成 / 启动 / 状态 / 清理 |

核心不变式：状态机只在 `meeting_engine.agent_loop` 一份，fake_agent 与
meeting_loop 通过注入 responder 复用，不可能漂移。

## 4. Pi 适配（与 opencode 版的差异）

### 4.1 LLM 唤醒

| opencode | pi |
|---|---|
| `opencode run --agent X --dir ... --format json --auto` | `pi --mode json --session-id ... --session-dir ... --model ... --thinking ... --append-system-prompt ... --approve --print` |
| agent 定义在 `.opencode/agent/*.md` | 身份在 `.pi/agent/*.md`，模型在 `pi-agent.json` |
| 无 `--dir` | 用 `subprocess.run(cwd=workdir)` |
| `--pure` | `--no-extensions --no-skills --no-prompt-templates --no-themes` |
| session 在全局 DB | session 文件在 `<base>/pi-sessions/` |

### 4.2 per-agent 配置

每个 work 内：

```
work-<agent>/
├── AGENTS.md            # 共享协议 + 背景（pi 自动加载）
├── .pi/agent/<agent>.md # 身份/分工（--append-system-prompt 注入）
├── pi-agent.json        # { model, thinking, prompt_file }
├── protocol.json        # 共享协议（提交 git）
└── question.md          # 讨论起点（提交 git）
```

`pi-agent.json` 是运行时配置的单一事实源，由 `meeting_loop.wake_llm` 读取并转为
`--model` / `--thinking` / `--append-system-prompt`。

### 4.3 默认模型

`_default_model()` 从 `~/.pi/agent/settings.json` 读取
`defaultProvider` / `defaultModel`，拼接为 `provider/model`。

### 4.4 pure 语义

Pi 没有 `--pure`；本项目映射为关闭外部 extension/skill/prompt-template/theme 加载，
保留内置工具与项目内 AGENTS.md。

## 5. spec 规格目录

复杂内容用 `--spec` / `--spec-gen`，与 CLI 内容参数互斥。

| spec 文件 | 作用 |
|---|---|
| `question.md` | 讨论起点（话题/立场/问题），整文件注入（跳首行） |
| `background.md` | 注入每个 work 的 AGENTS.md「背景」节 |
| `models.md` | 每 agent 的模型与 thinking（转成 `pi-agent.json`） |
| `agents/<name>.md` | 追加到对应 agent 的 `.pi/agent/<name>.md` |

已通过真实 Pi 讨论端到端验证（见 `docs/e2e-validation.md`）。

## 6. 生命周期

```
创建（--dir + --topic/--spec）→ 启动（--start）→ 观察（--status/--wait）
→ 收尾（result.md + concluded）→ 清理（--cleanup，保存 result.md 后删目录）
```

## 7. 测试策略

| 层 | 内容 |
|---|---|
| 单元 | meeting_core / stage4 / start_discussion / spec 生成 |
| FakeAgent 多进程 | 2~5 agent 并发、崩溃、收敛，验证确定性协议 |
| 真实 Pi 端到端 | 用真实 pi 跑 spec 讨论，验证注入、模型生效、result.md 产出 |

> 真实端到端验证由用户驱动补做，见 `docs/e2e-validation.md`。

## 8. 参考

- 本文档的协议部分源自 opencode 版 `meeting-mode-design.md`、`file-based-multi-agent-discussion.md`。
- opencode/pi 命令行与运行环境差异见 `docs/opencode-vs-pi.md`。
