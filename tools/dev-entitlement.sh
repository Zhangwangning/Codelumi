#!/usr/bin/env bash
# 真机权益切换（开发用）：free / lifetime
#
#   bash tools/dev-entitlement.sh free       # 变成免费态（验收付费墙）
#   bash tools/dev-entitlement.sh lifetime   # 重新签发买断凭证并写入
#
# 做法：直接替换 App Group 里的 entitlement.json —— 不用删 App、不动取件数据。
set -euo pipefail

DEVICE="${DEVICE:-00008140-001138A92E01801C}"
GROUP="group.com.jikezhang.codelumi"
MODE="${1:-free}"
DEVICECTL="$(xcrun --find devicectl 2>/dev/null || echo /Applications/Xcode.app/Contents/Developer/usr/bin/devicectl)"

push() {
  "$DEVICECTL" device copy to --device "$DEVICE" \
    --domain-type appGroupDataContainer --domain-identifier "$GROUP" \
    --source "$1" --destination "Library/Application Support/entitlement.json" >/dev/null
  "$DEVICECTL" device process launch --terminate-existing --device "$DEVICE" com.jikezhang.codelumi >/dev/null 2>&1 || true
}

case "$MODE" in
  free)
    cat > /tmp/ent-free.json <<'JSON'
{"isPro": false, "plan": "none", "updatedAt": "2026-11-07T03:00:00Z", "storeOwned": false}
JSON
    push /tmp/ent-free.json
    echo "✓ 已切到免费态（付费墙可验收）"
    ;;
  lifetime)
    CODE="$(python3 - <<'PY'
import json, urllib.request
# 从真机日志里拿不到设备码时，让它显式传入
print("")
PY
)"
    echo "请提供设备码（设置 › 激活 已移除，可从日志 codelumi-verify 里取）" >&2
    echo "用法：DEVICE_CODE=<32位HEX> bash tools/dev-entitlement.sh lifetime" >&2
    ;;
  *)
    echo "用法：bash tools/dev-entitlement.sh free|lifetime" >&2
    exit 1
    ;;
esac
