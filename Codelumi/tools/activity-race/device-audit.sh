#!/bin/bash
#
# Codelumi · 真机「实时活动」只读体检
#
# 解决的问题：锁屏与灵动岛**无法脚本化截图**，而「锁屏上到底挂着几张卡」
# 恰恰是用户唯一能看到、我们唯一看不到的东西。本脚本改成**问 App 自己**：
# 让它把 ActivityKit 账本里的在册活动逐条报出来（不注入数据、不主动动活动）。
#
# 用法：
#   tools/activity-race/device-audit.sh              # 体检 + 取回报告 + 复位为正常模式
#   tools/activity-race/device-audit.sh --no-restore # 体检后不重启（停在体检实例上）
#
# 前置：iPhone 已连线、已信任本机；App 已由 tools/install-device.sh 装到真机。
# 输出：stdout 直接打印；报告同时落盘在 /tmp/activity-audit.txt（可跨轮对比）。
#
# 判据：`running <= 1` 为 PASS（待办被清空时活动应全收掉，0 也是正确结果）。

set -euo pipefail

DEV_UDID="${DEV_UDID:-00008140-001138A92E01801C}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
BUNDLE="com.jikezhang.codelumi"
WAIT="${WAIT:-14}"                 # 体检窗口：需覆盖 audit-1（启动后 4s 才有）
OUT="${OUT:-/tmp/activity-audit.txt}"
CONSOLE_LOG="${CONSOLE_LOG:-/tmp/device-audit-console.log}"

C_OK="\033[32m"; C_WARN="\033[33m"; C_ERR="\033[31m"; C_DIM="\033[2m"; C_OFF="\033[0m"
ok()   { printf "${C_OK}✓${C_OFF} %s\n" "$1"; }
warn() { printf "${C_WARN}!${C_OFF} %s\n" "$1"; }
err()  { printf "${C_ERR}✗${C_OFF} %s\n" "$1"; }
say()  { printf "%b\n" "$1"; }

RESTORE=1
[[ "${1:-}" == "--no-restore" ]] && RESTORE=0

# ── 0. 设备在线检查 ──────────────────────────────────────────────────
if ! xcrun devicectl list devices 2>/dev/null | grep -q "${DEV_UDID}"; then
  err "找不到真机 ${DEV_UDID}（检查数据线与「信任此电脑」）"
  exit 1
fi
ok "真机在线"

# ── 1. 以体检模式启动（--console 桥接 stdout）─────────────────────────
rm -f "${CONSOLE_LOG}" "${OUT}"
say ""
say "── 以 ${C_DIM}activityAudit${C_OFF} 模式启动（只读，不注入任何数据）──"

# 🔴 `--console` 会一直跟随到 App 退出，必须丢到后台，否则脚本卡死在这里。
( DEVICECTL_CHILD_SCREEN=activityAudit \
    xcrun devicectl device process launch \
      --device "${DEV_UDID}" --terminate-existing --console "${BUNDLE}" \
      > "${CONSOLE_LOG}" 2>&1 & )

sleep "${WAIT}"

say ""
say "── stdout（--console 通道）──────────────────────────"
grep -a "codelumi-verify" "${CONSOLE_LOG}" | sed 's/^/  /' || warn "stdout 未取到读数（回落看落盘报告）"

# ── 2. 取回落盘报告（stdout 通道拿不到时的保险）────────────────────────
say ""
say "── 落盘报告（${C_DIM}Documents/activity-audit.txt${C_OFF}）──────────────"
# 🔴 --destination 必须是**文件路径**：给目录会报 "Is a directory"。
xcrun devicectl device copy from --device "${DEV_UDID}" \
  --domain-type appDataContainer --domain-identifier "${BUNDLE}" \
  --source Documents/activity-audit.txt --destination "${OUT}" >/dev/null 2>&1 \
  && ok "已取回 ${OUT}" || warn "取回失败（不影响 stdout 通道的读数）"

[[ -f "${OUT}" ]] && sed 's/^/  /' "${OUT}"

# ── 2.5 待办条数 —— 解释 running=0 的必要上下文 ──────────────────────
# 🔴 「活动数为 0」有两种完全不同的含义，只看活动数分不出来：
#      待办 0 → 收掉是**正确**行为（不该让锁屏挂着过期的取件码）；
#      待办 >0 → 卡本该在，这是**缺陷**。
#    在没有活动读数时也无法区分「节流/起不来」与「逻辑挡住了」。
#    所以必须把待办数一起读出来（数据在 App Group 容器，与 App 自身容器不同域）。
say ""
say "── 待办条数（${C_DIM}pickup-records.json${C_OFF}）──────────────────────"
RECORDS="${RECORDS:-/tmp/pickup-records.json}"
rm -f "${RECORDS}"
PENDING="?"
if xcrun devicectl device copy from --device "${DEV_UDID}" \
     --domain-type appGroupDataContainer --domain-identifier "group.${BUNDLE}" \
     --source "Library/Application Support/pickup-records.json" \
     --destination "${RECORDS}" >/dev/null 2>&1 && [[ -f "${RECORDS}" ]]; then
  # encoder 用的是 .prettyPrinted + .sortedKeys，键值格式固定，可直接计数
  TOTAL=$(grep -c '"isPickedUp"' "${RECORDS}" || true)
  PENDING=$(grep -c '"isPickedUp" : false' "${RECORDS}" || true)
  ok "记录 ${TOTAL} 条，其中待办（未取）${PENDING} 条"
else
  warn "未能取回记录文件（跳过该维度判定）"
fi

# ── 3. 判定 ─────────────────────────────────────────────────────────
say ""
say "── 判定 ──────────────────────────────────────"
# 🔴 只匹配读数行：脚手架说明文字里也含 "PASS/FAIL"，裸 grep FAIL 会误伤。
if grep -qE "running=[0-9]+ FAIL" "${CONSOLE_LOG}" "${OUT}" 2>/dev/null; then
  err "存在 FAIL —— 同时在册的活动 > 1，锁屏会显示重复卡"
  RC=1
elif [[ "${PENDING}" == "0" ]]; then
  ok "待办为 0，活动数为 0 —— 收起正确（锁屏上不该留过期取件码）"
  RC=0
elif [[ "${PENDING}" == "?" ]]; then
  ok "running <= 1：实时活动是单张"
  RC=0
elif grep -qE "running=0 " "${CONSOLE_LOG}" "${OUT}" 2>/dev/null; then
  err "待办有 ${PENDING} 条，却没有任何活动在册 —— 卡该在却不在"
  RC=1
else
  ok "待办 ${PENDING} 条，活动为单张 —— 正常"
  RC=0
fi

if grep -qE "audit-1 after-align running=[0-9]+ PASS" "${CONSOLE_LOG}" "${OUT}" 2>/dev/null; then
  ok "冷启动对齐后仍无重复（收敛稳定）"
else
  warn "未见 audit-1 读数 —— 窗口可能太短，调大 WAIT 再跑"
fi

# ── 4. 断开跟随并复位为正常模式 ──────────────────────────────────────
pkill -f "devicectl device process launch" 2>/dev/null || true
say ""
if [[ "${RESTORE}" == "1" ]]; then
  xcrun devicectl device process launch --device "${DEV_UDID}" \
    --terminate-existing "${BUNDLE}" >/dev/null 2>&1 \
    && ok "已复位为正常模式运行" || warn "复位失败，请手动打开一次Codelumi"
fi

exit "${RC}"
