# agents-meeting-discuss（Pi 版）——Meeting 文件式多 agent 讨论工具

这是 `agents-meeting-discuss` 的 **Pi 适配版**：底层 LLM 运行时从 opencode
换成 [Pi](https://pi.dev)（`pi` CLI）。设计、协议、状态机、目录结构沿用原版，
只替换"唤醒 LLM"这一薄层以及环境生成中与运行相关的细节。

一键创建、运行、清理一次 **Meeting 模式文件式多 agent 讨论**。

设计原则：**一次讨论 = 一个自包含目录**。目录内含 git bare 仓库（`repo.git`，
只为本讨论服务）+ 各 agent 工作 clone + 全部配置；Pi session 也存放在讨论目录内
（`pi-sessions/`），讨论完成后 `--cleanup` 先保存 `result.md` 到父级
（`<目录名>-result.md`）再删目录，不留全局残留。

## 目录结构

```
pi-agents-meeting-discuss/
├── start_discussion.py      # 主脚本（创建 / 启动 / 清理）
├── meeting_engine.py        # 唯一状态机（meeting→af→RR→result，确定性流程）
├── meeting_core.py          # 纯逻辑判定（校验器/冻结判定/读取点）
├── meeting_fs.py            # git/文件 I/O 层
├── meeting_loop.py          # 真实 LLM 薄壳（responder = 唤醒 pi）
├── fake_agent.py            # FakeAgent 薄壳（responder = 随机决策，测试用）
├── templates/               # 配置模板（AGENTS.md / agent prompt / .gitignore / spec README）
└── README.md
```

运行一次讨论后生成（示例 `--dir mymeet`）：

```
discussion-mymeet/
├── repo.git                 # 本地 bare 仓库（共享存储）
├── pi-sessions/             # Pi session 文件（随目录清理，不留全局残留）
├── work-a/                  # agent a 的工作区
│   ├── a/0001.md ...        # a 的消息（per-author）
│   ├── AGENTS.md            # 共享协议 + 背景（本地配置，pi 自动加载）
│   ├── .pi/agent/a.md       # agent prompt：per-agent 身份 + 分工（--append-system-prompt）
│   ├── pi-agent.json        # per-agent 运行时配置（model/thinking/prompt_file）
│   ├── protocol.json        # 共享协议（提交 git）
│   └── question.md          # 讨论起点：话题 + 立场 + 问题（提交 git）
├── work-b/  work-c/ ...     # 其他 agent
├── meeting_engine.py 等     # 运行脚本（自动复制）
├── loop-a.log ...           # 各 agent 循环日志
├── wake-logs/               # 每次唤醒记录完整命令行 + prompt（排错第一手段）
└── status-a.json ...        # 各 agent sessionID（运行时生成，base 根）
```

## 快速开始

```bash
# 1. 创建并启动一个 3-agent 立场辩论
cd pi-agents-meeting-discuss
python3 start_discussion.py --dir mymeet \
  --agents a,b,c \
  --topic "实现操作系统底层的最佳语言" \
  --stances '{"a": "倾向 C：最接近硬件", "b": "倾向 C++：抽象与性能", "c": "倾向 Rust：内存安全"}' \
  --pure --start

# 2. 观察讨论进展
tail -f discussion-mymeet/loop-a.log

# 3. 阻塞等待完成，打印 result.md 路径
python3 start_discussion.py --dir mymeet --wait

# 4. 清理（先保存 result.md 到父级，再删目录，含 pi-sessions）
python3 start_discussion.py --dir mymeet --cleanup
```

### 复杂内容用 spec 规格目录（与 CLI 内容参数互斥）

```bash
python3 start_discussion.py --spec-gen myspec --agents a,b,c
vim myspec/question.md myspec/background.md myspec/models.md myspec/agents/*.md
python3 start_discussion.py --dir mymeet --spec myspec/ --result-writer c --start
```

## 参数详解

| 参数 | 条件 | 默认 | 说明 |
|---|---|---|---|
| `--dir <name>` | 除 `--spec-gen` 外需要 | — | 讨论目录：含 `/` `~` `.` 等路径符 → 直接作为完整路径；否则 → 在 cwd 下创建 `discussion-<name>/` |
| `--topic <text>` | 创建且非 `--spec` 时需要 | — | 讨论主题 |
| `--agents <a,b>` | — | `a,b` | agent 名单，逗号分隔，**任意数量 ≥2**（`--spec` 时从 spec/agents/ 推断，不可传）|
| `--stances <json>` | — | 无 | 各方初始立场，JSON 对象 |
| `--models <json>` | — | 默认模型 | 各 agent 模型，JSON 对象 `{"a": "provider/model", ...}`；spec 模式从 `spec/models.md` 读 |
| `--max-meeting <n>` | — | 10 | meeting 阶段每 agent 发言配额 |
| `--max-rr <n>` | — | 7 | RR 阶段轮次配额 |
| `--background <text>` | — | 无 | 讨论背景（AGENTS.md 的「背景」节）|
| `--questions <Q1\|Q2>` | — | 无 | 待回答问题列表 |
| `--pure` | — | 关 | 创建时固化到 protocol.json：唤醒 pi 时加 `--no-extensions --no-skills --no-prompt-templates --no-themes`（外部加载关闭，内置工具不受影响）|
| `--start` | — | 关 | 生成后立即启动讨论循环 |
| `--skip-setup` | — | 关 | 跳过环境生成，只启动已有环境 |
| `--status` | — | 关 | 检查讨论状态（running / done / stopped / not-exists）|
| `--wait` | — | 关 | 阻塞等待讨论完成，完成后打印 result.md 路径 |
| `--cleanup` | — | 关 | 清理：保存 result.md → 删整个目录（含 pi-sessions）|
| `--spec-gen <dir>` | — | 无 | 生成 spec 骨架目录 |
| `--spec <dir>` | — | 无 | 讨论规格目录（内容源），与内容/参与者参数互斥 |

## Pi 适配说明

- **没有 `opencode run --agent`**：`meeting_loop.py` 改为每次唤醒执行
  `pi --mode json --session-id <id> --session-dir <base>/pi-sessions --approve --print <prompt>`。
- **per-agent 身份**：写入 `work-<p>/.pi/agent/<p>.md`，通过
  `--append-system-prompt` 注入；`AGENTS.md` 仍由 pi 自动从工作区加载。
- **模型与思考档位**：写入 `work-<p>/pi-agent.json`，唤醒时翻译为
  `--model provider/model` 与 `--thinking max/high/...`。
- **session 生命周期**：session 文件放在讨论目录 `pi-sessions/`，所以
  `--cleanup` 删除目录即完成 session 清理，不需要额外 DB 操作。
- **pure 近似**：Pi 没有 opencode 的 `--pure`；本项目把它映射为关闭外部
  extension/skill/prompt-template/theme 加载。

## 设计与迁移文档

- `docs/opencode-vs-pi.md`：记录从 opencode 版迁移到 Pi 版的完整分析、差异对比与代码映射。

## 讨论机制（双阶段协议）

```
meeting（自由发言）         → all-freezing（冻结级联）→ round-robin（RR 收尾）→ result
   LLM: message/freezing        loop: af                  loop: pass 轮转        loop: concluded
```

- 状态判定 = 聚合所有 agent 最后一条消息（bare 树）。
- LLM 只提供内容；协议字段/信号/判定全部由 loop 确定性完成。
- 每 commit 一条消息：`git log` 即讨论史。
- 无静默铁律：被唤醒必产出，无产出 loop 重试 + 代写。

## 依赖与平台

| 依赖 | 版本 | 用途 |
|---|---|---|
| Python | ≥3.9 | 脚本运行时（标准库，无第三方包）|
| pi | 已安装的 pi CLI | 讨论 agent 运行时 |
| git | 任意 | bare 仓库 + 每 commit 一条消息 |
| Linux | — | `pgrep`（进程检测）、`setsid`（后台启动）|

**可选环境变量**：
- `PI_CODING_AGENT_DIR`：Pi 配置目录（默认 `~/.pi/agent`），用于读取默认模型。
