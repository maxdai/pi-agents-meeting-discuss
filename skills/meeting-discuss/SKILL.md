---
name: meeting-discuss
description: 启动一个多 agent Pi 讨论，用多个独立视角分析复杂问题，并在结束后给出 result.md 结论。由用户手动调用。
disable-model-invocation: true
---

# Meeting Discuss（多 agent 讨论）

本 skill 让当前 Pi 会话启动一个独立的 `pi-agents-meeting-discuss` 多 agent 讨论，用多个独立视角分析复杂问题，并取回 `result.md` 结论。

## 何时使用

- 用户明确要求“开一个讨论”“多 agent 讨论”“用 meeting-discuss 分析”等。
- 当前问题复杂、需要多角度论证时，由用户决定是否调用。

## 重要

- 本 skill 由用户手动触发，不要自行判断触发。
- 讨论是异步的：启动后立即返回，但**主 pi 不能结束当前回合**。
- 启动后必须持续轮询状态，直到 `done` 或 `stopped`，再结束回合。
- 每次轮询后必须向用户报告进展。
- 读取 `result.md` 后必须清理讨论目录，避免残留 session。

## 使用步骤

### 1. 生成讨论 spec

运行：

```bash
../../scripts/discuss.sh --prepare "<问题>" [--background "<背景>"]
```

- `<问题>` 必填，是讨论主题。
- `--background` 可选；如果话题涉及敏感/禁忌边界，建议提供背景说明。

wrapper 会生成一个临时 spec 目录，并输出路径。

**向用户展示 spec 路径，请用户查看/编辑该目录**（可以补充背景、各 agent 视角等）。

**不要**让用户自行执行 `--start`。用户编辑完成后，告诉主 pi“继续”。

### 2. 启动讨论

用户确认“继续”后，主 pi 运行：

```bash
../../scripts/discuss.sh --start <spec目录>
```

启动后 wrapper 会输出：

- 讨论目录路径
- 查看状态命令
- 等待完成命令
- 清理命令

### 3. 持续轮询状态（不要结束回合）

启动后，**在当前回合内持续循环执行**以下命令，直到 `done` 或 `stopped`：

```bash
../../scripts/discuss.sh --status <目录>
```

可能的状态：

- `running`：讨论仍在进行，继续等待。
- `done`：讨论完成，`result.md` 已生成。
- `stopped`：讨论进程已结束，但没有 `result.md`——报告错误。
- `not-exists`：目录不存在，检查路径。

每次查看状态后，**必须向用户报告当前进展**：

- 当前状态（running / done / stopped）
- 已产生的消息数量或最新进展（可从 `git log` 或 `loop-*.log` 读取）
- 如果还在运行，说明会继续等待，并**继续循环调用 `--status`**，不要结束回合

只有出现 `done` 或 `stopped` 才停止轮询。

### 4. 等待完成（可选）

也可以阻塞等待：

```bash
../../scripts/discuss.sh --wait <目录>
```

完成时会打印 `result.md` 路径。

### 5. 读取 result.md

- 如果使用 `--wait`，按它打印的路径读取。
- 如果使用 `--status` 轮询到 `done`，默认读取：

```text
<目录>/work-c/result.md
```

读取后，向用户给出**摘要**，并明确提示：

> 完整结论见 `<result.md 路径>`。

### 6. 清理

读取完 `result.md` 后，必须清理讨论目录：

```bash
../../scripts/discuss.sh --cleanup <目录>
```

## 默认参数

启动讨论时 wrapper 使用以下默认值：

- agents：`a,b,c`（3 个）
- `--max-meeting 10`
- `--max-rr 5`
- `--pure`

## 错误处理

- 启动失败：wrapper 会输出具体错误，向用户报告即可。
- `stopped` 且没有 `result.md`：报告“讨论已结束但未生成结果”，不要继续等待。
- 清理失败：报告错误并检查目录。
