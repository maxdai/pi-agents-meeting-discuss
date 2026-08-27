# pi-agents-meeting-discuss 项目地图

本文件是审核/开发入口：先读它，理解每个文件职责。

## 项目是什么

Pi 版的多 agent 会议式讨论工具：多个 LLM agent（每个一个独立进程）通过共享 git
仓库交换消息，讨论一个话题，经过"自由讨论 → 冻结级联 → 轮转收尾"达成共识，
最终由 resultWriter 生成 result.md。

与 `agents-meeting-discuss`（opencode 版）的关系：核心状态机、git 文件协议、
测试装置完全一致，仅替换真实 LLM 适配薄层（`meeting_loop.py`）和环境生成细节
（`.pi/agent/*.md` + `pi-agent.json` + `pi-sessions/`）。

## npm / skill

- `package.json`：npm 包 `pi-meeting`，通过 `pi.skills` 暴露 skill。
- `scripts/discuss.sh`：wrapper（启动/状态/等待/清理）。
- `skills/meeting-discuss/SKILL.md`：手工触发 skill。

## 文档

- `docs/pi-meeting-design.md`：**Pi 版项目设计文档**。
- `docs/opencode-vs-pi.md`：opencode/pi 命令行与运行环境对比、迁移设计、代码映射。
- `docs/e2e-validation.md`：真实 Pi 讨论端到端验证记录。

## 源码

| 文件 | 职责 | 审核重点 |
|---|---|---|
| `meeting_core.py` | 纯逻辑判定函数（无 I/O） | 判定语义是否正确 |
| `meeting_fs.py` | 文件/git 层 | 边界条件、并发容错 |
| `meeting_engine.py` | **唯一状态机 + agent 主循环** | 状态机是否与设计一致 |
| `meeting_loop.py` | Pi 适配薄壳：唤醒 `pi`、session 复用、prompt 构造 | 是否只做 LLM 适配、CLI 参数是否正确 |
| `fake_agent.py` | 模拟 agent（测试用） | 与真实 responder 语义一致 |
| `start_discussion.py` | 环境生成/启动/状态/清理 | 参数语义、pi 配置文件生成 |

## Pi 关键差异

- `wake_llm()` 不再调用 `opencode run --agent`，改为调用 `pi --mode json`
  + `--session-id` + `--session-dir` + `--append-system-prompt`。
- 每个 work 内新增 `pi-agent.json`：`{model, thinking, prompt_file}`，供
  `meeting_loop` 构建 `--model` / `--thinking` / `--append-system-prompt`。
- session 文件集中在 `<base>/pi-sessions/`，随目录清理。
- `--pure` 映射为 pi 的关闭外部加载参数集合。

## 测试

- `tests/` 复用原版核心测试，并针对 pi 适配修改了生成/薄壳相关断言。
