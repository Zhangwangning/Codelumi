#!/bin/bash
# 查看当前构建（或已导出的 ipa）描述文件何时到期，以及还剩几天。
#
# 用法：
#   tools/profile-expiry.sh                     # 查真机构建产物
#   tools/profile-expiry.sh path/to/App.app     # 查指定 .app
#   tools/profile-expiry.sh path/to/X.ipa       # 查 ipa
set -uo pipefail

TARGET="${1:-/tmp/codelumi-device/Build/Products/Debug-iphoneos/Codelumi.app}"

if [[ ! -e "$TARGET" ]]; then
  echo "✗ 找不到 $TARGET（先跑一次 tools/install-device.sh）" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ "$TARGET" == *.ipa ]]; then
  unzip -p "$TARGET" "Payload/*.app/embedded.mobileprovision" > "$TMP/p.mobileprovision" 2>/dev/null
else
  cp "$TARGET/embedded.mobileprovision" "$TMP/p.mobileprovision" 2>/dev/null
fi

[[ -s "$TMP/p.mobileprovision" ]] || { echo "✗ 这个包里没有描述文件（App Store 包没有）" >&2; exit 1; }

security cms -D -i "$TMP/p.mobileprovision" 2>/dev/null \
  | plutil -convert xml1 -o - - 2>/dev/null > "$TMP/p.plist"

CREATED="$(awk '/<key>CreationDate<\/key>/{getline; gsub(/.*<date>|<\/date>.*/,""); print; exit}' "$TMP/p.plist")"
EXPIRES="$(awk '/<key>ExpirationDate<\/key>/{getline; gsub(/.*<date>|<\/date>.*/,""); print; exit}' "$TMP/p.plist")"
NAME="$(awk '/<key>Name<\/key>/{getline; gsub(/.*<string>|<\/string>.*/,""); print; exit}' "$TMP/p.plist")"

echo "描述文件：$NAME"
echo "签发时间：$CREATED"
echo "到期时间：$EXPIRES"

if [[ -n "$EXPIRES" ]]; then
  EXP_EPOCH="$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$EXPIRES" +%s 2>/dev/null)"
  NOW="$(date -u +%s)"
  if [[ -n "$EXP_EPOCH" ]]; then
    LEFT=$(( (EXP_EPOCH - NOW) / 86400 ))
    if (( LEFT < 0 )); then
      echo "状态：❌ 已过期 $(( -LEFT )) 天 —— App 打不开，重跑 tools/install-device.sh"
    else
      echo "状态：✅ 还剩 $LEFT 天"
    fi
  fi
fi
