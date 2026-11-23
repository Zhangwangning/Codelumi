#!/bin/zsh
# ============================================================================
# 主菜单行为验证（必须跑在真实 .app 里）
#
#   ./verify/menu/run.sh
#
# 为什么不能用 verify/theme 那套命令行 harness：
#   响应链分发起点是 keyWindow.firstResponder，命令行进程（无 bundle）拿不到
#   key window（实测 isKeyWindow 恒 false），测出来是假警报。
#
# 做法：复制 build.sh 的真实产物（Info.plist + zh-Hans.lproj + 图标），
#       只把可执行文件换成验证入口 —— 所以 Info.plist 不存在"两份要同步维护"的问题，
#       验证的就是真实构建配置。顺带能测「右键上下文菜单是否中文化」（也必须真实 .app 才能测）。
#
# 结果：/tmp/cc-menuchk-result.txt（同时打到终端）
# ============================================================================

set -e
cd "$(dirname "$0")/../.."

OUT="${CC_MENUCHK_OUT:-$HOME/Library/Caches/cc-menuchk}"
APP="$OUT/MenuCheck.app"
RESULT=/tmp/cc-menuchk-result.txt
BUNDLE_ID="com.jikezhang.codelumi.issuer.menucheck"
BASE="build/发码.app"

# ── 1. 真实产物（缺 zh-Hans.lproj 说明是旧构建，得重建才能验证本地化）──────
if [ ! -d "$BASE" ] || [ ! -d "$BASE/Contents/Resources/zh-Hans.lproj" ]; then
  echo "▸ build/发码.app 缺失或过旧，先构建 debug 版"
  ./build.sh debug | tail -2
fi

# ── 2. 准备验证用 .app ──────────────────────────────────────────────────
echo "▸ 准备 MenuCheck.app"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$BASE" "$APP"
# 改 bundle id：避免与真 App 在 LaunchServices 里抢注册
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "$APP/Contents/Info.plist" >/dev/null

# ── 3. 编译验证入口（复用真实 Src，排除 Src/main.swift 那个 App 入口）────
echo "▸ 编译验证入口"
xcrun swiftc -swift-version 5 -framework AppKit -framework CryptoKit \
  Src/Theme.swift Src/LicenseCore.swift Src/Pages.swift Src/SignPanel.swift Src/MainWindow.swift Src/MainMenu.swift \
  verify/menu/main.swift -o "$APP/Contents/MacOS/发码"

codesign --force --deep --sign - "$APP" 2>&1 | tail -1

# ── 4. 跑 ──────────────────────────────────────────────────────────────
echo "▸ 启动验证（真实 App，会短暂抢焦点）"
rm -f "$RESULT"
open "$APP"
for _ in {1..80}; do
  [[ -f "$RESULT" ]] && break
  sleep 0.25
done

if [[ ! -f "$RESULT" ]]; then
  echo "✗ 未拿到验证结果 —— App 可能没启动成功"
  exit 1
fi

echo
cat "$RESULT"
pkill -f "MenuCheck.app/Contents/MacOS/发码" 2>/dev/null || true

if grep -q "^判定：PASS" "$RESULT"; then
  exit 0
else
  exit 1
fi
