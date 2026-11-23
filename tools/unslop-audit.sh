#!/usr/bin/env bash
# 质量门禁：mobile-unslop（iOS / SwiftUI 的「AI 味代码」审计）
#
#   bash tools/unslop-audit.sh            # 审我们自己的源码，屏蔽字号规则
#   bash tools/unslop-audit.sh --all      # 不屏蔽任何规则
#   bash tools/unslop-audit.sh --json     # 机器可读
#   bash tools/unslop-audit.sh --changed  # 只审未提交改动
#
# 为什么默认屏蔽 SWIFT_FIXED_FONT_SIZE：
#   我们**故意**用数值字号（`AppTheme.TypeScale` 六档 × 全局倍率 `FontScale`），
#   小组件/灵动岛还要按像素对齐。这条规则看不穿这层封装，会刷 220 条噪音。
#   用户字号偏好由「设置 › 字体大小」负责，见 AGENTS「字号」一节。
set -uo pipefail
cd "$(dirname "$0")/.."

SRC=(Codelumi/Codelumi/CodelumiShared Codelumi/CodelumiWidget)
ARGS=(); MODE_ALL=0; ONLY_CHANGED=0
for a in "$@"; do
  case "$a" in
    --all) MODE_ALL=1 ;;
    --changed) ONLY_CHANGED=1 ;;
    *) ARGS+=("$a") ;;
  esac
done

TARGETS=()
[ "$ONLY_CHANGED" -eq 0 ] && TARGETS=("${SRC[@]}")

set +u
RAW=$(npx -y mobile-unslop-mcp@1.0.2 audit ${TARGETS[@]+"${TARGETS[@]}"} ${ARGS[@]+"${ARGS[@]}"} 2>&1)
set -u

if [ "$MODE_ALL" -eq 1 ]; then
  printf '%s\n' "$RAW"; exit 0
fi

# 过滤：字号规则本身 + 紧跟其后的那行代码 + 原始汇总（汇总里含被屏蔽的计数）
FILTERED=$(printf '%s\n' "$RAW" \
  | grep -v -e 'SWIFT_FIXED_FONT_SIZE' \
            -e '^    \.font(\.system(size:' \
            -e '^\(FAIL\|PASS\): .*file(s)')

ERR=$(printf '%s\n' "$FILTERED" | grep -c '  ERROR ' || true)
WARN=$(printf '%s\n' "$FILTERED" | grep -c '  WARN  ' || true)
printf '%s\n' "$FILTERED"
echo
echo "合计：$ERR 个 error，$WARN 个 warning（已屏蔽字号规则 SWIFT_FIXED_FONT_SIZE 及原始汇总行）"
[ "$ERR" -gt 0 ] && exit 1
exit 0
