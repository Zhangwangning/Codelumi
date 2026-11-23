#!/bin/zsh
# ============================================================================
# Codelumi · 凭证签发 · 快捷指令专用 Shell 片段
#
# 用法：把本文件**全文**粘进 macOS 快捷指令的「运行 Shell 脚本」动作
#       （解释器选 zsh；动作的「输入」接两行文本）。
#
# 输入（两行）：
#   第 1 行 = 买家设备码（大小写、连字符、空格都行，会自动归一化）
#   第 2 行 = 档位：trial（临时 7 天）/ lifetime（买断，永久）
#
# 输出：
#   成功 → 一行凭证（237 字符，不带换行），直接进剪贴板发给买家
#   失败 → ERR| 开头的错误说明，退出码 1
#
# 只依赖 macOS 自带：date / printf / base64 / tr / sed / openssl / python3
# ============================================================================

KEY="/Volumes/ZWN/Downloads/Project/Codelumi/tools/license-gen/private-key.pem"

if [ ! -f "$KEY" ]; then
  print -- "ERR|找不到私钥：$KEY（外置卷没挂载？）"
  exit 1
fi

INPUT=$(cat)
DEV=$(printf '%s' "$INPUT" | sed -n '1p' | tr -dc '0-9A-Fa-f' | tr 'a-f' 'A-F')
SVC=$(printf '%s' "$INPUT" | sed -n '2p' | tr -d '[:space:]')

if [ ${#DEV} -ne 32 ]; then
  print -- "ERR|设备码归一化后是 ${#DEV} 位，应为 32 位十六进制"
  exit 1
fi

case "$SVC" in
  trial)    DAYS=7 ;;
  lifetime) DAYS=0 ;;
  *) print -- "ERR|档位必须是 trial / lifetime"; exit 1 ;;
esac

I=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ "$DAYS" -gt 0 ]; then
  E=$(date -u -v+"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ)
  PAYLOAD=$(printf '{"s":"%s","d":"%s","i":"%s","e":"%s"}' "$SVC" "$DEV" "$I" "$E")
else
  PAYLOAD=$(printf '{"s":"%s","d":"%s","i":"%s"}' "$SVC" "$DEV" "$I")
fi

B64=$(printf '%s' "$PAYLOAD" | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '=')

SIG=$(printf 'CLIP1.%s' "$B64" | /usr/bin/openssl dgst -sha256 -sign "$KEY" | /usr/bin/python3 -c '
import sys, base64
d = sys.stdin.buffer.read()
i = 2
rlen = d[i+1]; r = d[i+2:i+2+rlen]; i += 2+rlen
slen = d[i+1]; s = d[i+2:i+2+slen]
r = r.lstrip(b"\x00").rjust(32, b"\x00")
s = s.lstrip(b"\x00").rjust(32, b"\x00")
sys.stdout.write(base64.urlsafe_b64encode(r+s).decode().rstrip("="))
')

print -rn -- "CLIP1.$B64.$SIG"
