#!/bin/bash
# 小组件截图（真实渲染验收）
#
# 用途：桌面小组件在模拟器上无法脚本化添加，唯一能拿到「真实渲染证据」的办法是
# 在 App 内用**同一份视图代码**按小组件尺寸渲染（App/Views/WidgetPreviewGallery.swift）。
# 本脚本按「分类 × 尺寸」逐个出图，每张都精确落在目标那一块上。
#
# 用法：
#   tools/widget-shots.sh              # 全功能档（PRO=1）
#   PRO=0 tools/widget-shots.sh        # 免费档（出「免费版」标记与 3 条截断）
#
# PRO 由 `WidgetSnapshot.preview()` 读取（0/1 强制档位）—— 命令行改不了真实权益文件，
# 靠它一次拍出两种档位。2026-10-30 起免费档额度是 3 条（原 4 条）。
#
# ⚠️ 变量一律用 ${} 包起来：中文全角括号紧跟在 $VAR 后面时，
#    非 UTF-8 locale 会把多字节字符的首字节也算进变量名（`$PRO）` → 变量 `PRO\xef`），
#    报 "unbound variable" 且报错行看着完全正常 —— 极难排查。
#
# ⚠️ 每次 launch 前必须 **terminate + sleep 3**：simctl terminate 是异步的，
#    旧进程还没死就 launch，SIMCTL_CHILD_* 注入会被**静默忽略** ——
#    App 会以前一次的参数启动（看起来像「参数没生效」或「拍到了别的页面」）。
#
# ⚠️ 脚本会先 uninstall 再 install：示例数据只在存储为空时写入，
#    不重置就看不到新增的餐饮 / 出行 / 票夹样例（App Group 一并被清掉）。

set -uo pipefail

DEVICE=${DEVICE:-C4C58A0C-6879-480E-A42F-7F8B1B1D9F5C}
BUNDLE=${BUNDLE:-com.jikezhang.codelumi}
APP=${APP:-/tmp/codelumi-dd/Build/Products/Debug-iphonesimulator/Codelumi.app}
OUT=${OUT:-/Volumes/ZWN/Downloads/Project/Codelumi/Design-Snapshots}
PRO=${PRO:-1}

if [ ! -d "$APP" ]; then
  echo "找不到构建产物：${APP}（先跑一次 xcodebuild build）" >&2
  exit 1
fi

mkdir -p "$OUT"

echo "▸ 启动模拟器 $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

echo "▸ 重置并安装（PRO=${PRO}）"
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
sleep 3
xcrun simctl uninstall "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"

shot() {  # $1=分类  $2=尺寸  $3=输出文件名
  local cat="$1" size="$2" name="$3"
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  sleep 3
  SIMCTL_CHILD_SCREEN=widgets \
  SIMCTL_CHILD_WIDGET_CAT="$cat" \
  SIMCTL_CHILD_WIDGET_SIZE="$size" \
  SIMCTL_CHILD_PRO="$PRO" \
  xcrun simctl launch "$DEVICE" "$BUNDLE" >/dev/null
  sleep 6
  xcrun simctl io "$DEVICE" screenshot --type=png "/tmp/$name.png" >/dev/null 2>&1
  # simctl 不能直写外置卷，先落 /tmp 再拷
  cp "/tmp/$name.png" "$OUT/$name.png"
  echo "  ✓ $name.png"
}

suffix=""
[ "$PRO" = "0" ] && suffix="-free"

echo "▸ 出图"
shot express   large              "widget-express-large$suffix"
shot express   extraLargePortrait "widget-express-xlp$suffix"
shot express   extraLarge         "widget-express-xl$suffix"
shot express   medium             "widget-express-medium$suffix"
shot express   small              "widget-express-small$suffix"
shot dining    large              "widget-dining-large$suffix"
shot travel    medium             "widget-travel-medium$suffix"
shot tickets   medium             "widget-tickets-medium$suffix"

echo "▸ 完成，输出在 $OUT"
