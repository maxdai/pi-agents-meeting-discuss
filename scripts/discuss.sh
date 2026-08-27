#!/usr/bin/env bash
#
# pi-meeting wrapper
#
# 用法：
#   ./scripts/discuss.sh --prepare "<问题>" [--background "<背景>"]
#   ./scripts/discuss.sh --start <spec目录>
#   ./scripts/discuss.sh --status <dir>
#   ./scripts/discuss.sh --wait <dir>
#   ./scripts/discuss.sh --cleanup <dir>
#
# 设计文档：docs/pi-meeting-skill-design.md
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PYTHON="${PYTHON:-python3}"
START_DISCUSSION="$ROOT_DIR/start_discussion.py"
SPEC_README_TPL="$ROOT_DIR/templates/spec-readme.md.tpl"

DEFAULT_AGENTS="a,b,c"
DEFAULT_MAX_MEETING=10
DEFAULT_MAX_RR=5

usage() {
    cat <<'USAGE_EOF'
用法:
  $0 --prepare "<问题>" [--background "<背景>"]
  $0 --start <spec目录>
  $0 --status <dir>
  $0 --wait <dir>
  $0 --cleanup <dir>

默认讨论参数:
  agents=a,b,c  max-meeting=10  max-rr=5  --pure
USAGE_EOF
}

fail() {
    echo "错误: $*" >&2
    exit 1
}

require_dir() {
    local dir="$1"
    [ -n "$dir" ] || fail "缺少目录参数"
    [ -d "$dir" ] || fail "目录不存在: $dir"
}

cmd_status() {
    local dir="$1"
    require_dir "$dir"
    "$PYTHON" "$START_DISCUSSION" --dir "$dir" --status
}

cmd_wait() {
    local dir="$1"
    require_dir "$dir"
    "$PYTHON" "$START_DISCUSSION" --dir "$dir" --wait
}

cmd_cleanup() {
    local dir="$1"
    require_dir "$dir"
    "$PYTHON" "$START_DISCUSSION" --dir "$dir" --cleanup
}

# 读取主 pi 的 model/thinking（缺失时回退默认）
read_pi_model_thinking() {
    local provider="${PI_PROVIDER:-}"
    local model="${PI_MODEL:-}"
    local thinking="${PI_REASONING_LEVEL:-}"
    local full_model=""
    if [ -n "$provider" ] && [ -n "$model" ]; then
        full_model="$provider/$model"
    elif [ -n "$model" ]; then
        full_model="$model"
    fi
    echo "$full_model|$thinking"
}

cmd_prepare() {
    local topic="" background=""
    if [ "$#" -lt 1 ]; then
        usage >&2
        exit 2
    fi
    topic="$1"
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --background)
                [ "$#" -ge 2 ] || fail "--background 需要一个值"
                background="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "未知参数: $1（--prepare 只接受 <问题> 和 --background）"
                ;;
        esac
    done
    [ -n "$topic" ] || fail "问题不能为空"

    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    local spec_dir="$PWD/pi-meeting-spec-${stamp}"
    mkdir -p "$spec_dir/agents"

    # question.md
    cat > "$spec_dir/question.md" <<EOF
# question.md——说明行，不注入

# 讨论主题：$topic

## 初始立场（可选，每参与者一行）
- a: 立场
- b: 立场
- c: 立场

## 待回答的问题（可选）
- 问题
EOF

    # background.md
    if [ -n "$background" ]; then
        cat > "$spec_dir/background.md" <<EOF
# background.md——说明行，不注入

$background
EOF
    else
        cat > "$spec_dir/background.md" <<EOF
# background.md——说明行，不注入

EOF
    fi

    # models.md：延用主 pi 的 model/thinking，缺失则 default
    local mt
    mt="$(read_pi_model_thinking)"
    local pi_model="${mt%%|*}"
    local pi_thinking="${mt##*|}"
    {
        echo "# models.md——说明行，不注入"
        for agent in a b c; do
            if [ -n "$pi_model" ] && [ -n "$pi_thinking" ]; then
                echo "$agent: $pi_model, $pi_thinking"
            elif [ -n "$pi_model" ]; then
                echo "$agent: $pi_model"
            elif [ -n "$pi_thinking" ]; then
                echo "$agent: default, $pi_thinking"
            else
                echo "$agent: default"
            fi
        done
    } > "$spec_dir/models.md"

    # agents/*.md
    for agent in a b c; do
        cat > "$spec_dir/agents/$agent.md" <<EOF
# $agent.md——说明行，不注入

EOF
    done
    printf 'a\nb\nc\n' > "$spec_dir/agents/.order"

    # README
    if [ -f "$SPEC_README_TPL" ]; then
        cp "$SPEC_README_TPL" "$spec_dir/README.md"
    fi

    cat <<OUTPUT_EOF
已生成讨论 spec:
  $spec_dir

请查看/编辑该目录，补充背景、各 agent 视角等。
编辑完成后，告诉我“继续”，我会自动启动讨论。
OUTPUT_EOF
}

cmd_start() {
    local spec_dir="$1"
    require_dir "$spec_dir"
    [ -f "$spec_dir/question.md" ] || fail "spec 缺少 question.md: $spec_dir"

    local session_id="${PI_SESSION_ID:-}"
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    local dir_name="discuss"
    if [ -n "$session_id" ]; then
        dir_name="${dir_name}-${session_id}"
    fi
    dir_name="${dir_name}-${stamp}"
    local dir_path="$PWD/$dir_name"

    if ! "$PYTHON" "$START_DISCUSSION" --dir "$dir_path" --spec "$spec_dir" --max-meeting "$DEFAULT_MAX_MEETING" --max-rr "$DEFAULT_MAX_RR" --pure --start; then
        fail "讨论启动失败，请查看上方输出"
    fi

    # spec 已被消费，删除临时 spec
    rm -rf "$spec_dir"

    cat <<OUTPUT_EOF
讨论已启动
目录: $dir_path
查看状态: $0 --status $dir_path
等待完成: $0 --wait $dir_path
清理: $0 --cleanup $dir_path

说明:
- 完成后 result.md 默认由 resultWriter=c 生成，位于 $dir_path/work-c/result.md
- 执行 --wait 会在完成时打印 result.md 路径
- 读取 result.md 后请执行 --cleanup 清理讨论目录
OUTPUT_EOF
}

if [ "$#" -ge 1 ]; then
    case "$1" in
        --prepare)
            shift
            cmd_prepare "$@"
            exit $?
            ;;
        --start)
            [ "$#" -ge 2 ] || fail "--start 需要 spec 目录参数"
            cmd_start "$2"
            exit $?
            ;;
        --status)
            [ "$#" -ge 2 ] || fail "--status 需要讨论目录参数"
            cmd_status "$2"
            exit $?
            ;;
        --wait)
            [ "$#" -ge 2 ] || fail "--wait 需要讨论目录参数"
            cmd_wait "$2"
            exit $?
            ;;
        --cleanup)
            [ "$#" -ge 2 ] || fail "--cleanup 需要讨论目录参数"
            cmd_cleanup "$2"
            exit $?
            ;;
        -h|--help)
            usage
            exit 0
            ;;
    esac
fi

usage >&2
exit 2
