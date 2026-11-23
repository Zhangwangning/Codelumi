#!/bin/zsh
# ============================================================================
# Codelumi · 发码工具 —— 构建并安装到「应用程序」
#
# 用法：
#   ./install.sh              # release 构建 + 安装到 /Applications/发码.app
#   ./install.sh debug        # debug 构建（带符号，便于排查）+ 安装
#   ./install.sh release --no-build   # 跳过构建，只把现有产物复制过去
#
# 为什么必须装到本机卷（重要）：
#   仓库位于外挂卷 /Volumes/...。实测（macOS 27.2，noowners 挂载的 APFS 外挂盘），
#   一个由 `open` 启动的 App 读该卷上的文件时，stat() 立即返回，
#   但紧接着的 open() 会在内核里永久挂起且不弹授权框 —— 表现为「双击没反应」。
#   装到 /Applications（本机卷）后彻底绕开该门禁。
#   App 的日常数据（私钥、台账）本就落在 ~/Library/Application Support/CodelumiIssuer/，
#   仓库仅作一次性导入来源，因此安装副本是自包含的。
# ============================================================================

set -e
cd "$(dirname "$0")"

APP_NAME="发码"
BUILD_OUT="build/${APP_NAME}.app"
DST="/Applications/${APP_NAME}.app"
CONFIG="${1:-release}"
SKIP_BUILD=0
[[ "$2" == "--no-build" || "$1" == "--no-build" ]] && SKIP_BUILD=1

if [ "$SKIP_BUILD" = "0" ]; then
  echo "▸ 构建（${CONFIG}）"
  ./build.sh "$CONFIG" | tail -4
else
  echo "▸ 跳过构建"
fi

[ -d "$BUILD_OUT" ] || { echo "✗ 找不到产物：$BUILD_OUT"; exit 1; }

echo "▸ 安装到 ${DST}"
# 先退出正在运行的旧实例，否则会因占用导致替换不完整
pkill -f "${DST}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
sleep 0.4
rm -rf "$DST"
cp -R "$BUILD_OUT" "$DST"

# 本地构建复制不应带隔离标记；保险起见清一次
xattr -dr com.apple.quarantine "$DST" 2>/dev/null || true

echo "▸ 校验签名"
# 注意用 -v（校验磁盘上的签名）而不是 -dv（只打印签名信息）。
# -v 成功时是**静默**的，所以要显式报出来，否则看日志会以为没执行。
if codesign -v "$DST" 2>/dev/null; then
  echo "  ✓ valid on disk（adhoc 签名，复制后仍有效）"
else
  echo "  ✗ 签名校验失败："
  codesign -v "$DST" 2>&1 | sed 's/^/    /'
fi

echo "▸ 注册到 LaunchServices（Spotlight / 启动台可搜到）"
LSR="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSR" -f "$DST" 2>/dev/null || true

echo "▸ 完成"
du -sh "$DST" | awk '{print "  体积：" $1}'
echo "  位置：$DST"
