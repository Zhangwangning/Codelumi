#!/bin/bash
#
# Codelumi · 实时活动「单一性」竞态回归
#
# 背景（2026-09-25）：主人反馈锁屏上**有时会同时出现两张实时活动卡**，
#   两张的取件码还不同（118-5-6178 / 110-5-6178）。根因有两条，都会各起一张活动：
#     ① 读-判-写竞态：`Activity.activities` 读 + `Activity.request` 非原子，
#        两次 sync 重叠（records 的 didSet 与回前台 reload 挤在同一秒）→ 各起一张；
#     ② 账本同步延迟：新拉起的进程读到空列表 → 又 request 一张（→ 两张内容不同）。
#   而 `converge` 原先只 `update(activities.first)`，多余的孤儿卡**永不消失**。
#
# 本脚本用 `SCREEN=activityRace` 脚手架把这两条复现出来并验收修复，
#   判据：每个阶段 `running <= 1`（0 也正确 —— 无待办/非会员时本该收光）。
#
# 用法：
#   Codelumi/tools/activity-race/run.sh              # 用默认模拟器
#   Codelumi/tools/activity-race/run.sh <UDID>       # 指定模拟器
#
# ⚠️ 必须注入 PLAN=yearly：实时活动是 VIP 权益，全新安装的模拟器没有凭证，
#    第 1 道门就会 endAll()，表现为 running=0 —— 极易误判成"模拟器不支持活动"。
#
# 预期输出（修复后）：
#   race-0 audit running=0|1 ...              ← 启动瞬间的真实账本
#   race-A baseline        running=1 PASS
#   race-B concurrent-burst running=1 PASS    ← 修复前这里是 3
#   race-C spaced           running=1 PASS    ← 修复前这里是 3
#   race-D after-sync       running=1 PASS    ← 修复前这里收敛不了（5）
#   race-E late-arrival     running=1 PASS    ← 延迟复查收掉"迟到的旧活动"

set -euo pipefail

UDID="${1:-281DCBD3-D8CC-4262-A82A-1BFDD6FED586}"   # iPhone 16 Pro · iOS 27.0
# 优先 Xcode 正式版；本机若无 beta，退回 Xcode.app（2026-10-30 修：原先硬编码 beta 路径会直接失败）
if [[ -d /Applications/Xcode-beta.app ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
else
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$SCRIPT_DIR/../../"
DD="$PROJ_ROOT/build-sim"
BUNDLE="com.jikezhang.codelumi"
WAIT="${WAIT:-34}"

C_OK="\033[32m"; C_ERR="\033[31m"; C_DIM="\033[2m"; C_OFF="\033[0m"
ok()  { printf "${C_OK}✓${C_OFF} %s\n" "$1"; }
dim() { printf "${C_DIM}%s${C_OFF}\n" "$1"; }

printf "── 构建 ──────────────────────────────────────\n"
cd "$PROJ_ROOT"
xcodebuild -project Codelumi.xcodeproj -scheme Codelumi -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$DD" build 2>&1 | grep -E "error:|BUILD" || true

APP="$DD/Build/Products/Debug-iphonesimulator/Codelumi.app"
[[ -d "$APP" ]] || { printf "${C_ERR}✗${C_OFF} 构建产物不存在：$APP\n"; exit 1; }
ok "构建完成"

printf "\n── 从干净状态安装 ────────────────────────────\n"
# 🔴 先卸载：报告文件是 append 写法的，不清干净就分不清是哪一轮的读数
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
sleep 1
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
ok "已安装到 $UDID"

printf "\n── 跑竞态取证（约 ${WAIT}s）──────────────────\n"
# RACE_N / RACE_GAP 透传给 App（连发次数 / 间隔），不设则用脚手架默认值
SIMCTL_CHILD_SCREEN=activityRace \
SIMCTL_CHILD_PLAN=yearly \
SIMCTL_CHILD_RACE_N="${RACE_N:-24}" \
SIMCTL_CHILD_RACE_GAP="${RACE_GAP:-0}" \
  xcrun simctl launch "$UDID" "$BUNDLE"
sleep "$WAIT"

CID="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
REPORT="$CID/Documents/race-report.txt"
[[ -f "$REPORT" ]] || { printf "${C_ERR}✗${C_OFF} 报告不存在：$REPORT\n"; exit 1; }

printf "\n── 报告 ──────────────────────────────────────\n"
cat "$REPORT"

printf "\n── 判定 ──────────────────────────────────────\n"
# ⚠️ 只匹配「running=N FAIL」这个**读数**，不能用裸 `grep FAIL` ——
#    脚手架里那句「模拟主人截图里的两张卡，此处不看判定」的说明文字也含 FAIL，
#    会把一次全通过的跑判成失败（实测踩过）。
if grep -qE "running=[0-9]+ FAIL" "$REPORT"; then
  printf "${C_ERR}✗${C_OFF} 存在 FAIL 读数 —— 单一性不变式被破坏，见上面各行\n"
  exit 1
fi
ok "全部 PASS：任一阶段在册活动数都 <= 1"

# 归档一份到脚本目录，便于对照历史
STAMP="$(date +%Y%m%d-%H%M%S)"
cp "$REPORT" "$SCRIPT_DIR/report-$STAMP.txt"
dim "已归档：$SCRIPT_DIR/report-$STAMP.txt"
