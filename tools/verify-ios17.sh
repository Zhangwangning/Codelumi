#!/usr/bin/env bash
# iOS 17 兼容回归（等运行时装好后再跑；部署目标 2026-11-11 已降到 17.0）
#
#   bash tools/verify-ios18.sh
#
# 做三件事：
#   1. 找一个 iOS 17.x 的模拟器运行时；没有就报错退出（提示怎么装）
#   2. 用它建/复用一台 iPhone 16 Pro 模拟器，装上 Debug 构建
#   3. 逐屏截图到 /tmp/ios17/，供人工对比 iOS 27 的观感
set -euo pipefail

OUT=/tmp/ios17
mkdir -p "$OUT"
APP=/tmp/codelumi-verify/Build/Products/Debug-iphonesimulator/Codelumi.app
BUNDLE=com.jikezhang.codelumi

# 1) 找 iOS 17 运行时
RUNTIME=$(xcrun simctl list runtimes | grep -E "iOS 17" | grep -oE "com\.apple\.CoreSimulator\.SimRuntime\.iOS-17[^ ]*" | head -1 || true)
if [ -z "$RUNTIME" ]; then
  echo "✗ 没有 iOS 17 运行时。先装："
  echo "    xcodebuild -downloadPlatform iOS -buildVersion 17.5"
  exit 1
fi
echo "✓ 运行时：$RUNTIME"

# 2) 建/复用模拟器
DEVICE=$(xcrun simctl list devices | grep "iOS 17" | grep -oE "[0-9A-F-]{36}" | head -1 || true)
if [ -z "$DEVICE" ]; then
  echo "→ 新建模拟器"
  DEVICE=$(xcrun simctl create "iPhone15Pro-iOS17" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro "$RUNTIME")
fi
echo "✓ 设备：$DEVICE"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true

# 3) 安装并发版截图
[ -d "$APP" ] || { echo "✗ 先跑一次模拟器构建：/tmp/codelumi-verify"; exit 1; }
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true

shoot() { # $1=SCREEN 名 $2=额外 env（可空）
  local name="$1"; shift
  env SIMCTL_CHILD_SCREEN="$name" SIMCTL_CHILD_SKIP_PERM=1 SIMCTL_CHILD_SKIP_ONBOARDING=1 "$@" \
    xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 8
  xcrun simctl io "$DEVICE" screenshot "$OUT/$name.png" >/dev/null 2>&1 || true
  echo "  · $name.png"
}

echo "→ 截图"
shoot ""
shoot detail
shoot settings
shoot appearance
shoot aiCapability
shoot widgets
shoot help

echo "✓ 完成：$OUT"
echo "重点看：玻璃材质是否发灰可接受、'液态玻璃'开关是否隐藏、Apple 智能是否显示低版本说明页"
