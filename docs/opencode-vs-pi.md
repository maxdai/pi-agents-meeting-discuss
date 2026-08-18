# agents-meeting-discuss 的 Pi 迁移设计文档

> 本文记录从 opencode 版 `agents-meeting-discuss` 迁移到 Pi 版的完整过程：
> 先理解原项目原理，再对比 opencode/pi 的命令行与运行环境，最后得出代码改造方案。
> 代码实现在本仓库根目录，本文是设计与决策记录。

---

## 1. 原项目原理摘要

原项目 `agents-meeting-discuss` 的核心是一套“文件式多 agent 会议讨论协议”。

### 1.1 总体架构

```
每个 agent 一个独立进程 + 独立 git clone（work-a/、work-b/...）
                 │
                 ▼
        共享 bare 仓库（repo.git）
                 │
                 ▼
  每个 agent 通过 commit/push 消息，pull 获取他人消息
```

- 一次讨论 = 一个自包含目录
- 所有状态从 bare 仓库推导
- 每 commit 一条消息，`git log` 即讨论史

### 1.2 消息模型

| 类型 | 谁写 | 作用 |
|---|---|---|
| `message` | LLM | 讨论内容 |
| `freezing` | LLM / loop | 表示无话可说，冻结 |
| `all-freezing` | loop | 确认全员冻结 |
| `pass` | LLM / loop | RR 阶段确认无异议 |
| `concluded` | loop | 收尾 |

### 1.3 关键设计

1. **无静默铁律**：被唤醒必须产出，失败由 loop 重试或代写。
2. **发言锁**：写 `freezing` 后不再发 `message`。
3. **配额确定性**：`max_meeting` 耗尽后 loop 直接写 `freezing`。
4. **状态从 git 推导**：聚合每个 agent 最后一条消息，不依赖时间戳。
5. **流程控制穿透锁**：af / pass / concluded 不受发言锁阻塞。

### 1.4 状态机

```
meeting（自由发言）
  → 全员冻结（freezing/af）
  → all-freezing
  → starter 启动 RR（pass）
  → 全员 pass
  → resultWriter 写 result.md + loop 写 concluded
  → 结束
```

### 1.5 代码分层

| 文件 | 职责 |
|---|---|
| `meeting_core.py` | 纯逻辑判定，无 I/O |
| `meeting_fs.py` | git/文件操作 |
| `meeting_engine.py` | 唯一状态机 + 协议信号 |
| `meeting_loop.py` | 真实 LLM 薄壳 |
| `fake_agent.py` | 测试用模拟 LLM |
| `start_discussion.py` | 环境生成 / 启动 / 清理 |

核心不变式：**状态机只有一份**，fake_agent 与 meeting_loop 都通过 responder 注入复用。

---

## 2. OpenCode 命令行与运行环境

### 2.1 本项目用到的 opencode 命令

```bash
opencode run \
  --agent <agent名> \
  --session <sessionID> \
  --dir <workdir> \
  --format json \
  --auto \
  [--pure] \
  "<prompt>"
```

### 2.2 参数含义

| 参数 | 作用 |
|---|---|
| `--agent <name>` | 使用哪个 agent 定义 |
| `--session <id>` | 续用指定 session |
| `--dir <path>` | 工作目录 |
| `--format json` | 输出 JSON 事件流 |
| `--auto` | 自动批准权限 |
| `--pure` | 不加载外部插件 |
| `--variant` | 模型思考档位 |
| `-m, --model` | 指定模型 |

### 2.3 运行环境

| 项目 | 位置 / 机制 |
|---|---|
| 配置 | `~/.config/opencode/`，支持 `OPENCODE_CONFIG` 等环境变量 |
| 数据 | `~/.local/share/opencode/` |
| Session DB | `~/.local/share/opencode/opencode.db`（SQLite） |
| Agent 定义 | 项目 `.opencode/agent/*.md`，全局 `~/.config/opencode/agent/*.md` |
| Agent frontmatter | `description`、`mode`、`model`、`variant` 等 |
| 上下文 | 自动读取 `AGENTS.md` 等 |
| 权限 | `--auto` 或 permission 规则 |

---

## 3. Pi 命令行与运行环境

### 3.1 本项目适配后的 Pi 命令

```bash
pi \
  --mode json \
  --session-id <id> \
  --session-dir <base>/pi-sessions \
  --model <provider/model> \
  --thinking <max|high|...> \
  --append-system-prompt <workdir>/.pi/agent/<agent>.md \
  --approve \
  --print \
  "<prompt>"
```

### 3.2 参数含义

| 参数 | 作用 |
|---|---|
| `--mode json` | JSON 事件流 |
| `--print / -p` | 非交互单次运行 |
| `--session-id <id>` | 固定 session id，不存在则创建 |
| `--session-dir <dir>` | session 文件目录 |
| `--model <provider/model>` | 指定模型 |
| `--thinking <level>` | 思考档位 |
| `--append-system-prompt <path>` | 追加 system prompt 内容 |
| `--approve / -a` | 自动信任项目本地文件 |
| `--no-extensions` 等 | 替代 `--pure` 的近似关闭外部加载 |

### 3.3 运行环境

| 项目 | 位置 / 机制 |
|---|---|
| 配置目录 | `~/.pi/agent/`，可用 `PI_CODING_AGENT_DIR` 覆盖 |
| Session | 默认 `~/.pi/agent/sessions/<encoded-cwd>/`，可用 `--session-dir` 重定向 |
| 配置 | `~/.pi/agent/settings.json`，含 `defaultProvider` / `defaultModel` |
| 认证 | `~/.pi/agent/auth.json` |
| Agent 概念 | 无 opencode agent 机制，用 `--append-system-prompt` 注入身份 |
| 上下文 | 默认自动读取 `AGENTS.md` / `CLAUDE.md` |

---

## 4. 核心差异对比

| 维度 | opencode | pi | 改造影响 |
|---|---|---|---|
| 工作目录 | `--dir <path>` | 无，用 `cwd=workdir` | `meeting_loop.py` 必须传 `cwd` |
| Agent 身份 | `--agent` + `.opencode/agent/*.md` | 无 agent，`--append-system-prompt` 注入 | 改为 `.pi/agent/*.md` |
| 模型 | frontmatter `model` / `-m` | `--model` | 写入 `pi-agent.json` |
| 思考档位 | frontmatter `variant` / `--variant` | `--thinking` | 写入 `pi-agent.json` |
| Session 复用 | `--session` + 全局 DB | `--session-id` + 文件 | 用 status JSON 保存 id |
| Session 清理 | 删 DB session | 删 `pi-sessions/` 目录 | 简化 cleanup |
| pure | `--pure` | 无直接等价 | `--no-extensions --no-skills --no-prompt-templates --no-themes` |
| 自动批准 | `--auto` | `--approve` | 直接替换 |
| 默认模型 | `opencode debug config` | `settings.json` | 改 `_default_model()` |
| AGENTS.md | 自动加载 | 自动加载 | 保持不变 |

---

## 5. 代码改造映射

### 5.1 `meeting_loop.py`

原：

```python
cmd = [
    "opencode", "run",
    "--agent", agent,
    "--dir", workdir,
    "--format", "json",
    "--auto",
]
if pure:
    cmd.append("--pure")
```

改：

```python
cmd = [
    "pi", "--mode", "json",
    "--session-id", sid,
    "--session-dir", session_dir,
]
if pure:
    cmd += ["--no-extensions", "--no-skills", "--no-prompt-templates", "--no-themes"]
if model:
    cmd += ["--model", model]
if thinking:
    cmd += ["--thinking", thinking]
if prompt_file:
    cmd += ["--append-system-prompt", os.path.join(workdir, prompt_file)]
cmd += ["--approve", "--print", prompt]

subprocess.run(cmd, cwd=workdir, ...)
```

### 5.2 `start_discussion.py`

- 写入 `.pi/agent/<agent>.md`，替代 `.opencode/agent/<agent>.md`
- 写入 `pi-agent.json`：

```json
{
  "model": "provider/model",
  "thinking": "max",
  "prompt_file": ".pi/agent/a.md"
}
```

- `_default_model()` 从 `~/.pi/agent/settings.json` 读取：

```python
{
  "defaultProvider": "opencode-go",
  "defaultModel": "deepseek-v4-flash"
}
```

- `cleanup_discussion()` 不再查 opencode DB，直接删除讨论目录（含 `pi-sessions/`）

### 5.3 模板

- `templates/agent.md.tpl` 改为纯 Markdown 身份 prompt
- `templates/gitignore.tpl` 忽略 `.pi/`、`pi-agent.json`

---

## 6. 测试与验证

- 原核心协议测试保持不变，验证协议层未受运行时替换影响
- 新增 Pi 薄壳单测：
  - session id 生成
  - pi JSON header 解析
  - `pi-agent.json` 读取
  - `wake_llm` 命令构造
- 原 102 项测试已跑通

---

## 7. 结论

Pi 迁移不需要改动协议层与状态机，只需替换“LLM 适配层”和“环境生成层”：

1. 将 agent 定义文件从 opencode 格式改为 pi 的 `--append-system-prompt` 纯文本
2. 将 model / variant 改为 `pi-agent.json` + `--model` / `--thinking`
3. 将 session 生命周期收拢到讨论目录内，简化清理
4. 将 `--dir` 改为 `cwd=workdir`
5. 将 `--pure` / `--auto` 映射为 pi 对应参数

这样既保留了原项目经过大量测试验证的确定性协议，又能复用 Pi 的会话、模型和工具能力。
