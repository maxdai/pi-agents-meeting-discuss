#!/usr/bin/env bash
#
# pi-meeting wrapper
#
# 用法：
#   ./scripts/discuss.sh "<问题>" [--background "<背景>"]
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

DEFAULT_AGENTS="a,b,c"
DEFAULT_MAX_MEETING=10
DEFAULT_MAX_RR=5

usage() {
    cat <<'USAGE_EOF'
用法:
  $0 "<问题>" [--background "<背景>"]
  $0 --status <dir>
  $0 --wait <dir>
  $0 --cleanup <dir>

启动模式默认参数:
  agents=a,b,c  max-meeting=10  max-rr=5  --pure
USAGE_EOF
}

fail() {
    echo "错误: $*" >&2
    exit 1
}

require_dir() {
    local dir="$1"
    [ -n "$dir" ] || fail "缺少讨论目录参数"
    [ -d "$dir" ] || fail "讨论目录不存在: $dir"
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

cmd_start() {
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
                fail "未知参数: $1（启动模式只接受 <问题> 和 --background）"
                ;;
        esac
    done
    [ -n "$topic" ] || fail "问题不能为空"

    local session_id="${PI_SESSION_ID:-}"
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    local dir_name="discuss"
    if [ -n "$session_id" ]; then
        dir_name="${dir_name}-${session_id}"
    fi
    dir_name="${dir_name}-${stamp}"
    local dir_path="$PWD/$dir_name"

    local cmd=( "$PYTHON" "$START_DISCUSSION" --dir "$dir_path" --agents "$DEFAULT_AGENTS" --topic "$topic" --max-meeting "$DEFAULT_MAX_MEETING" --max-rr "$DEFAULT_MAX_RR" --pure )
    if [ -n "$background" ]; then
        cmd+=( --background "$background" )
    fi
    cmd+=( --start )

    if ! "${cmd[@]}"; then
        fail "讨论启动失败，请查看上方输出"
    fi

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

cmd_start "$@"
