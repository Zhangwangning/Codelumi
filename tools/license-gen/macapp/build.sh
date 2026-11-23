#!/bin/zsh
# ============================================================================
# Codelumi · 发码工具（macOS 客户端）构建脚本
#
# 只依赖 Command Line Tools：xcrun swiftc + codesign，不需要 Xcode 工程。
# 产物：build/发码.app
#
# 注意（实测坑）：
#   · 必须用 `xcrun swiftc`，不要 `SWIFTC=$(xcrun -f swiftc)` 再执行 —— 会丢资源目录
#   · 不要加 -target <arch>-apple-macosx13.0：CLT 只带本机 SDK 的 Swift 标准库
# ============================================================================

set -e
cd "$(dirname "$0")"

APP_NAME="发码"
BUNDLE_ID="com.jikezhang.codelumi.issuer"
OUT="build/${APP_NAME}.app"
CONFIG="${1:-release}"

echo "▸ 清理"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

# 让 Spotlight 别索引 build/ —— 这里有一份同名的「发码.app」副本，但它在**外挂卷**上，
# 从 Finder 双击会因跨卷门禁永久卡死（见 install.sh 文件头）。藏掉它，只留 /Applications 那份可被搜到。
touch build/.metadata_never_index

echo "▸ 图标"
# 图标由 icon/make_icon.swift 程序化生成；未生成过则先跑一次
if [ ! -f "icon/AppIcon.icns" ]; then
  xcrun swift icon/make_icon.swift
fi
cp "icon/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"

echo "▸ 写 Info.plist"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>Codelumi 发码</string>
    <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>zh-Hans-CN</string>
        <string>en</string>
    </array>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 极客ZHANG · 保留所有权利</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 简体中文资源目录。
# 🔴 这个 .lproj 的**存在本身**就会让 AppKit 把「系统提供的那部分 UI」按中文渲染 ——
#    最直观的是 NSTextView 的右键上下文菜单：没有它时是硬编码英文
#    （Cut / Copy / Paste / Paste and Match Style），有了才变「剪切 / 拷贝 / 粘贴 / 粘贴并匹配样式」。
#    实测依据：修复前 `Bundle.main.localizations == []`（空）。
#    （「编辑」菜单的中文标题 + ⌘C/⌘V 快捷键由 Src/MainMenu.swift 提供，与本目录无关，
#      两者是独立的两件事：一个是自绘菜单，一个是让系统 UI 认中文。）
mkdir -p "$OUT/Contents/Resources/zh-Hans.lproj"
cat > "$OUT/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'STRINGS'
/* 简体中文资源占位 + 显示名本地化。 */
CFBundleDisplayName = "Codelumi 发码";
STRINGS

echo "▸ 编译（${CONFIG}）"
if [ "$CONFIG" = "debug" ]; then
  xcrun swiftc -swift-version 5 \
    -framework AppKit -framework CryptoKit \
    Src/*.swift -o "$OUT/Contents/MacOS/${APP_NAME}"
else
  xcrun swiftc -O -swift-version 5 \
    -framework AppKit -framework CryptoKit \
    Src/*.swift -o "$OUT/Contents/MacOS/${APP_NAME}"
fi

echo "▸ 临时签名"
codesign --force --deep --sign - "$OUT" 2>&1 | tail -2

echo "▸ 刷新图标缓存（LaunchServices）"
# 不刷新的话，Finder / Dock 可能继续显示旧图标或通用底板（实测需重注册 + 重启 Finder）
LSR="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSR" -f "$(pwd)/$OUT" 2>/dev/null || true

echo "▸ 完成：$OUT"
du -sh "$OUT" | awk '{print "  体积：" $1}'
