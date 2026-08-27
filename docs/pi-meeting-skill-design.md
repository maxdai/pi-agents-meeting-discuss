# pi-meeting skill 设计文档

> 状态：设计讨论定稿（2026-08-26）
> 目标：让 Pi 在运行中能够方便地调用 `pi-agents-meeting-discuss`，以多 agent 讨论方式辅助当前单 agent Pi 会话。

## 1. 定位

- 这是一个 **Pi skill**，由用户**手工启动**，不依赖 Pi 自动判断触发。
- 对应 Pi skill 的 `disable-model-invocation: true`：不出现在系统提示的 `<available_skills>` 中，不污染 LLM 信息。
- 用户通过 `/skill:meeting-discuss` 调用。

## 2. npm 包

- npm 包名：`pi-meeting`
- **不注册 bin 命令**，只作为 Pi 扩展携带：
  - Python 核心（`start_discussion.py` 等）
  - wrapper 脚本（`scripts/discuss.sh`）
  - skill（`skills/meeting-discuss/SKILL.md`）
- 通过 `package.json` 的 `pi.skills` 字段让 Pi 自动发现 skill。
- 发布流程沿用 `pi-sdk-web` 方式：
  - 手动发布，不配置自动发版
  - `npm version` → commit + tag → `npm publish` → `git push --follow-tags`
  - 发版前必须用户确认“是否修改完成”，版本号由用户确认后提升。

## 3. 项目结构

保持现有仓库结构，直接在根目录增加 npm 包装：

```text
pi-agents-meeting-discuss/
├── package.json                  # name: pi-meeting; pi.skills: ["./skills/meeting-discuss"]
├── scripts/
│   └── discuss.sh                # wrapper
├── skills/
│   └── meeting-discuss/
│       └── SKILL.md              # name: meeting-discuss; disable-model-invocation: true
├── start_discussion.py           # 现有 Python 核心，不动
├── meeting_*.py                  # 现有 Python 核心，不动
├── templates/
├── tests/
└── docs/
```

## 4. skill 定义

- name：`meeting-discuss`
- disable-model-invocation：`true`
- description（中文）：
  > 启动一个多 agent Pi 讨论，用多个独立视角分析复杂问题，并在结束后给出 result.md 结论。由用户手动调用。

## 5. wrapper 接口

```bash
# 启动（立即返回）
./scripts/discuss.sh "<问题>" [--background "<背景>"]

# 观察
./scripts/discuss.sh --status <dir>
./scripts/discuss.sh --wait <dir>

# 清理
./scripts/discuss.sh --cleanup <dir>
```

### 参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `<问题>` | 是 | 讨论主题/问题 |
| `--background` | 否 | 背景说明；不传则无背景 |
| `--status <dir>` | 是（该模式） | 查看讨论状态 |
| `--wait <dir>` | 是（该模式） | 阻塞等待讨论完成 |
| `--cleanup <dir>` | 是（该模式） | 清理讨论目录 |

## 6. 默认讨论参数

- agents：3
- `--max-meeting 10`
- `--max-rr 5`
- `--pure`

## 7. 讨论目录

- 创建位置：当前工作目录（cwd）下
- 命名：自动唯一，格式 `discuss-<sessionid>-<时间戳>/`；`sessionid` 取自环境变量 `PI_SESSION_ID`（如果有），否则只用时间戳。
- 不添加 session name（Pi 未暴露 `PI_SESSION_NAME`，暂不解析 session 文件）。

## 8. 核心流程（SKILL.md 教给主 pi）

1. 用户手工 `/skill:meeting-discuss "<问题>" [background]`
2. 主 pi 运行 `./scripts/discuss.sh "<问题>" [--background "..."]`，启动后立即返回
3. wrapper 输出精确信息：讨论目录、后续可用命令
4. 主 pi 轮询 `./scripts/discuss.sh --status <dir>`：
   - `done` → 读取 result.md
   - `running` → 继续等
   - `stopped` 且没有 result.md → 报告错误
5. 读取 result.md 后，主 pi 自己阅读并总结，并提示完整内容在 result.md
6. 最后执行 `./scripts/discuss.sh --cleanup <dir>`

## 9. wrapper 输出

尽量精确描述，避免 LLM 误判。启动后输出示例：

```text
讨论已启动
目录: <cwd>/discuss-<sessionid>-<时间戳>/
查看状态: ./scripts/discuss.sh --status <目录>
等待完成: ./scripts/discuss.sh --wait <目录>
清理: ./scripts/discuss.sh --cleanup <目录>
```

## 10. 错误处理

- 没传问题：输出明确用法，退出非零。
- `--status / --wait / --cleanup` 指向不存在的目录：输出明确错误，退出非零。
- 启动失败（找不到 python3、项目路径不对等）：输出具体错误原因。

## 11. 结果摘要

- wrapper 不生成摘要。
- 主 pi 读取 result.md 后自己总结，并提示完整内容在 result.md。

## 12. 状态监控

- v1 使用现有 `--status` 的 `running / done / stopped / not-exists`。
- 如果实际使用中发现“running 但无进展”需要区分，再修改 `pi-agents-meeting-discuss` 的 `check_status`（例如增加 `running-active` / `running-stalled`）。

## 13. 后续可能的扩展

- 各 agent 视角参数（`--stances` 等）：当前不预留，等真正需要时再加。
- 状态监控增强：视实际使用效果决定。
- 其他 wrapper 行为调整：以实际效果为准，同步更新本文档。

## 14. 维护规则

- 对 skill 的任何修改，必须同步更新本文档。
