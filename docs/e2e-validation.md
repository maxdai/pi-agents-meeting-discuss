# Pi 版真实讨论端到端验证记录

> 日期：2026-08-19
> 目标：用**真实 pi** 跑一场多 agent 讨论，验证 spec 规格目录的各个部分是否真实生效，并产出 result.md。

## 1. 验证环境

- 项目：`pi-agents-meeting-discuss`
- 运行方式：`start_discussion.py --spec`
- 参与者：a、b（2 agents）
- 模型：`opencode-go/deepseek-v4-flash`（经 `pi-agent.json` 配置）
- 配额：`--max-meeting 2 --max-rr 2`

## 2. 验证用 spec（临时，已清理）

```
verify-spec/
├── question.md      # 话题 + 初始立场 + 待答问题 + QUESTION_MARKER_Q
├── background.md    # 背景 + BACKGROUND_MARKER_BG
├── models.md        # a: opencode-go/deepseek-v4-flash, b: default
└── agents/
    ├── a.md         # MODEL_MARKER_A / ALPHA-1
    └── b.md         # MODEL_MARKER_B / BRAVO-2
```

## 3. 验证点与结果

| 验证点 | 方法 | 结果 |
|---|---|---|
| question.md 注入 | 检查 work-a/work-b 的 question.md 含 QUESTION_MARKER_Q | ✅ 生效 |
| background 注入 | 检查两个 work 的 AGENTS.md「背景」节含 BACKGROUND_MARKER_BG | ✅ 生效 |
| per-agent 身份注入 | 检查 `.pi/agent/a.md` 含 ALPHA-1、`.pi/agent/b.md` 含 BRAVO-2 | ✅ 生效 |
| models 生成 | 检查 `pi-agent.json` 的 model/thinking | ✅ 生效 |
| model 真正被 pi 采用 | 在 pi 的 session 文件里查实际 model | ✅ `deepseek-v4-flash` |
| 完整协议链路 | 观察 git 历史 / loop 日志 | ✅ message → freezing → af → RR pass → result.md → concluded |
| result.md 产出 | 检查 work 与父级 result.md | ✅ 生成并保存 |

## 4. 产物

- 讨论目录：`discussion-verifyspec/`（已清理）
- 结果：`discussion-verifyspec-result.md`（已清理）
- pi session：`pi-sessions/`（随目录清理）

## 5. 结论

- spec 各文件（question/background/models/agents）的注入在真实 Pi 讨论中全部生效。
- 模型/thinking 配置通过 `pi-agent.json` → `--model/--thinking` 被 Pi 真实采用。
- 完整会议协议（自由发言 → 冻结 → RR 收尾）跑通，并生成了 `result.md`。
- 本次验证未修改任何项目代码。
