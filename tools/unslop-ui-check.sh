#!/usr/bin/env bash
# 自动化部分的「去 AI 味」检查（人工审计见 skills/unslop-ios/）
#
#   bash tools/unslop-ui-check.sh
#
# 查的是**能机器判定的**几条，其余（层次、节奏、文案口气）靠人看截图。
set -uo pipefail
cd "$(dirname "$0")/.."
VIEWS=Codelumi/Codelumi/Views
FILES=$(find "$VIEWS" -name '*.swift')
FAIL=0
say() { printf '%s\n' "$1"; }
bad() { FAIL=1; printf '  ✗ %s\n' "$1"; }

say "== 1. 界面里出现 emoji =="
HITS=$(grep -rnP '"[^"]*[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}][^"]*"' $FILES 2>/dev/null | grep -v "//" | head -10 || true)
[ -n "$HITS" ] && { printf '%s\n' "$HITS"; bad "界面文案含 emoji，换 SF Symbols 或删掉"; } || say "  ✓ 无"

say "== 2. 设置/教程页里写死字号（应走 TypeScale）=="
HITS=$(grep -rn "\.system(size: 1[0-9]" Codelumi/Codelumi/Views/ProfileView.swift \
        Codelumi/Codelumi/Views/SettingsHelpAbout.swift \
        Codelumi/Codelumi/Views/TrainingDataView.swift 2>/dev/null | head -10 || true)
[ -n "$HITS" ] && { printf '%s\n' "$HITS"; bad "设置类页面出现数值字号，改用 AppTheme.TypeScale"; } || say "  ✓ 无"

say "== 3. Text 里残留 Markdown 星号 =="
HITS=$(grep -rn 'Text("[^"]*\*\*' $FILES 2>/dev/null | grep -v '\.richText' | head -10 || true)
[ -n "$HITS" ] && { printf '%s\n' "$HITS"; bad "字面量里的 ** 不会变粗体，改用 .richText 或去掉"; } || say "  ✓ 无"

say "== 4. 相邻 SettingsRow 标题重复（同页重复条目）=="
DUP=$(grep -rh "SettingsRow(symbol:" -A1 $FILES 2>/dev/null \
  | grep -o 'title: "[^"]*"' | sort | uniq -d | head -10 || true)
[ -n "$DUP" ] && { printf '%s\n' "$DUP"; say "  ⚠ 同名行出现多次（可能是不同页，人工确认是否同页重复）"; } || say "  ✓ 无"

say "== 5. 夸张/销售式文案 =="
HITS=$(grep -rnE '赋能|无缝|极致|超级|重新定义|一键解锁|懂你|不容错过' $FILES 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+: *///' | grep -vE '^[^:]+:[0-9]+: *//' | head -10 || true)
[ -n "$HITS" ] && { printf '%s\n' "$HITS"; bad "命中 AI/营销味词，改成事实陈述"; } || say "  ✓ 无"

say "== 6. 同一文件里 hInset 出现 2 次以上（父子叠加的嫌疑）=="
DUP=$(grep -rc "padding(.horizontal, AppTheme.hInset)" $FILES 2>/dev/null \
  | awk -F: '$2>=2 {print $1" ("$2" 次)"}' | head -8 || true)
[ -n "$DUP" ] && { printf '%s
' "$DUP"; say "  ⚠ 逐个人工确认：一处页面级 + 一处内容级叠加会双倍缩进"; } || say "  ✓ 无"

say ""
if [ "$FAIL" -eq 0 ]; then say "结果：机器可判定的项都通过 ✅"; else say "结果：有命中项，按上面提示改 ⚠"; fi
exit "$FAIL"
