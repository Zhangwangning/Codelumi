#!/usr/bin/env python3
# ============================================================================
# Codelumi · 离线凭证签发（OpenSSL + 标准库版）
#
# 与 issue.mjs **完全等价**（同一算法、同一私钥、可互相验签），
# 区别只在依赖：本脚本只用 macOS 自带的 `/usr/bin/openssl` 与
# `/usr/bin/python3`（纯标准库），不需要 Node。
#
# 为什么要这一版：**快捷指令**要调用它。
#   · Node 路径在本机是包管理器装的（可能换版本/被清掉）；
#   · `/usr/bin/python3` + `/usr/bin/openssl` 是 macOS 自带的，最稳。
#
# 用法（与 issue.mjs 一致）：
#   python3 issue-openssl.py --plan 7d          --device <32位HEX>        # 7 天
#   python3 issue-openssl.py --plan 30d         --device <码>             # 30 天
#   python3 issue-openssl.py --plan 180d        --device <码>             # 180 天
#   python3 issue-openssl.py --plan 1y          --device <码>             # 一年（365 天）
#   python3 issue-openssl.py --plan forever     --device <码>             # 永久
#   （也支持 --plan 7天 / 30天 / 半年 / 一年 / 永久 这类写法）
#   python3 issue-openssl.py --service trial    --device <32位HEX>        # 等价旧写法，默认 7 天
#   python3 issue-openssl.py --service lifetime --device <码> --note "订单尾号1234"  # 买断，永久
#   python3 issue-openssl.py --check "CLIP1.xxx.yyy"
#
# ── 凭证格式（四个字节细节，错一个就"签得出但验不过"）──────────────────
#
#   ① payload 是 JSON，字段**固定顺序** s / d / i / e / n，**无空格**
#      例：{"s":"trial","d":"5028…","i":"2026-09-24T14:13:26Z","e":"2026-10-01T14:13:26Z"}
#      —— JSON 文本本身就是签名对象的一部分，多一个空格签名就不同。
#   ② 该 JSON 的 UTF-8 字节做 **base64url**（`+`→`-`、`/`→`_`、**去掉 `=`**）
#   ③ 签名对象是 **`CLIP1.<payloadB64>` 整段**（含前缀，挡版本重放）
#   ④ 签名 = **ECDSA P-256 + SHA-256，输出 P1363（r‖s 各 32 字节 = 64 字节）**。
#      这是最大的坑：openssl 默认吐 **DER**（可变长、带 ASN.1 头），
#      必须转成定长 64 字节，否则 App 侧 CryptoKit 的
#      `ECDSASignature(rawRepresentation:)` 直接不认。
# ============================================================================

import base64
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
KEY_PATH = os.path.join(HERE, 'private-key.pem')

PREFIX = 'CLIP1'
SERVICES = ('trial', 'lifetime')

# 卖的五档有效期 → (service, days)。2026-10-31 主人定：
#   7 天 / 30 天 / 180 天 / 一年 / 永久。
# 前三档与一年都是「带到期时间的凭证」（service=trial），只是天数不同；
# 永久走 lifetime，payload 不带 e 字段。
PLANS = {
    '7d': ('trial', 7),
    '30d': ('trial', 30),
    '180d': ('trial', 180),
    '1y': ('trial', 365),
    'forever': ('lifetime', 0),
}
# 允许的写法别名（中文/口语也认，免得每次翻文档）
PLAN_ALIASES = {
    '7': '7d', '7天': '7d', 'week': '7d',
    '30': '30d', '30天': '30d', 'month': '30d', '1m': '30d',
    '180': '180d', '180天': '180d', '半年': '180d', '6m': '180d',
    '365': '1y', '365天': '1y', '一年': '1y', '12m': '1y',
    'permanent': 'forever', 'lifetime': 'forever', '永久': 'forever', '买断': 'forever',
}
DEVICE_RE = re.compile(r'^[0-9A-F]{32}$')

OPENSSL = '/usr/bin/openssl'


# ── 基础工具 ────────────────────────────────────────────────────────────────

def b64url(raw: bytes) -> str:
    """base64url：+ → -，/ → _，去掉尾部 =（与 issue.mjs 一致）"""
    return base64.urlsafe_b64encode(raw).decode('ascii').rstrip('=')


def from_b64url(text: str) -> bytes:
    pad = '=' * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + pad)


def normalize_device(raw: str) -> str:
    """与 App 侧 LicenseDevice.normalize / issue.mjs 必须完全一致：大写 + 只留 0-9A-F"""
    return re.sub(r'[^0-9A-F]', '', str(raw).upper())


def iso_now(offset_days: int = 0) -> str:
    """ISO8601 **不带毫秒**（App 侧 .iso8601 解码器不接受小数秒）"""
    moment = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=offset_days)
    return moment.strftime('%Y-%m-%dT%H:%M:%SZ')


# ── DER ⇄ P1363 ─────────────────────────────────────────────────────────────
#
# DER:  30 <len> 02 <rlen> <r> 02 <slen> <s>
# P1363: r‖s，各固定 32 字节（不足左侧补 0x00）
#
# 这一步是"手搓"的核心。openssl 只吐 DER，App 只认 P1363，中间必须转换。

def der_to_p1363(der: bytes) -> bytes:
    if not der or der[0] != 0x30:
        raise ValueError('不是合法的 DER 签名')

    i = 1
    if der[i] & 0x80:                       # 长形式长度
        n = der[i] & 0x7F
        i += 1 + n
    else:
        i += 1

    if der[i] != 0x02:
        raise ValueError('DER 里找不到 r')
    rlen = der[i + 1]
    r = der[i + 2: i + 2 + rlen]
    i += 2 + rlen

    if der[i] != 0x02:
        raise ValueError('DER 里找不到 s')
    slen = der[i + 1]
    s = der[i + 2: i + 2 + slen]

    # DER 整数会把最高位为 1 的值前置一个 0x00，转 P1363 时要去掉再补齐 32 字节
    r = r.lstrip(b'\x00').rjust(32, b'\x00')
    s = s.lstrip(b'\x00').rjust(32, b'\x00')
    return r + s


def p1363_to_der(sig: bytes) -> bytes:
    """反向转换：供 openssl 验签用（openssl 只认 DER）"""
    if len(sig) != 64:
        raise ValueError('P1363 签名必须是 64 字节，当前 %d' % len(sig))

    def enc_int(chunk: bytes) -> bytes:
        chunk = chunk.lstrip(b'\x00') or b'\x00'
        if chunk[0] & 0x80:                 # 最高位为 1 要补 0x00 才不会当成负数
            chunk = b'\x00' + chunk
        return b'\x02' + bytes([len(chunk)]) + chunk

    body = enc_int(sig[:32]) + enc_int(sig[32:])
    return b'\x30' + bytes([len(body)]) + body


# ── openssl 调用 ────────────────────────────────────────────────────────────

def _run(cmd, stdin: bytes = b''):
    proc = subprocess.run(cmd, input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError('%s 失败：%s' % (cmd[1], proc.stderr.decode('utf-8', 'replace').strip()))
    return proc.stdout


def sign_data(data: bytes) -> bytes:
    """ECDSA P-256 + SHA-256 签名，返回 64 字节 P1363"""
    der = _run([OPENSSL, 'dgst', '-sha256', '-sign', KEY_PATH], stdin=data)
    return der_to_p1363(der)


def verify_data(data: bytes, sig_p1363: bytes) -> bool:
    """验签。注意：openssl 的 `-signature` 要的是**文件路径**，
    用 `/dev/stdin` 会和「数据也从 stdin 进」打架（实测读到空 → 误判无效），
    所以签名先落临时文件。"""
    der = p1363_to_der(sig_p1363)
    sig_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.der') as fh:
            fh.write(der)
            sig_path = fh.name
        proc = subprocess.run(
            [OPENSSL, 'dgst', '-sha256', '-verify', PUBLIC_KEY_PATH, '-signature', sig_path],
            input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        return proc.returncode == 0
    finally:
        if sig_path:
            try:
                os.remove(sig_path)
            except OSError:
                pass


# 公钥：从私钥现导（验签用），落在系统临时目录，不污染仓库
PUBLIC_KEY_PATH = os.path.join(tempfile.gettempdir(), 'codelumi-license-pub.tmp.pem')


def ensure_public_key():
    pub = _run([OPENSSL, 'pkey', '-in', KEY_PATH, '-pubout'])
    with open(PUBLIC_KEY_PATH, 'wb') as fh:
        fh.write(pub)


# ── 参数解析（与 issue.mjs 同名同义）────────────────────────────────────────

def parse_args(argv):
    opts, i = {}, 0
    while i < len(argv):
        token = argv[i]
        if token.startswith('--'):
            name = token[2:]
            nxt = argv[i + 1] if i + 1 < len(argv) else None
            if nxt is not None and not nxt.startswith('--'):
                opts[name] = nxt
                i += 2
                continue
            opts[name] = True
        i += 1
    return opts


def build_payload(service: str, device: str, days: int, note) -> dict:
    payload = {'s': service, 'd': device, 'i': iso_now()}
    if service != 'lifetime':
        payload['e'] = iso_now(days)
    if isinstance(note, str):
        payload['n'] = note
    return payload


def issue(service: str, device: str, days: int, note) -> str:
    payload = build_payload(service, device, days, note)
    # separators 去掉空格；ensure_ascii=False 保持与 JS 一致（本场景全 ASCII，无实际差异）
    payload_json = json.dumps(payload, separators=(',', ':'), ensure_ascii=False)
    payload_b64 = b64url(payload_json.encode('utf-8'))
    signed = ('%s.%s' % (PREFIX, payload_b64)).encode('utf-8')
    signature = sign_data(signed)
    return '%s.%s.%s' % (PREFIX, payload_b64, b64url(signature))


def do_check(code: str) -> int:
    parts = code.strip().split('.')
    if len(parts) != 3 or parts[0] != PREFIX:
        print('✗ 格式不对：应当是 CLIP1.<payload>.<signature> 三段')
        return 1

    signed = ('%s.%s' % (parts[0], parts[1])).encode('utf-8')
    try:
        sig = from_b64url(parts[2])
        payload = json.loads(from_b64url(parts[1]).decode('utf-8'))
    except Exception as exc:
        print('✗ 解析失败：%s' % exc)
        return 1

    ensure_public_key()
    try:
        ok = verify_data(signed, sig)
    finally:
        try:
            os.remove(PUBLIC_KEY_PATH)
        except OSError:
            pass

    print('✓ 签名有效' if ok else '✗ 签名无效')
    print('  载荷： %s' % json.dumps(payload, separators=(',', ':'), ensure_ascii=False))

    if payload.get('d'):
        print('  绑定设备：%s' % payload['d'])
        print('  ⚠️ 这串码只在那台设备上生效 —— 通知买家别转发（也没用）。')
    else:
        print('  ⚠️ 这张凭证没有绑定设备（d 缺失）—— App 会拒绝导入。')

    if payload.get('e'):
        expired = payload['e'] <= iso_now()
        print('  到期：%s%s' % (payload['e'], '（已过期）' if expired else ''))
    else:
        print('  到期：永久')
    return 0 if ok else 1


# ── 入口 ────────────────────────────────────────────────────────────────────

def main(argv) -> int:
    if not os.path.exists(KEY_PATH):
        print('找不到私钥：%s' % KEY_PATH)
        print('这个文件不进仓库 —— 换机器时记得单独拷过来。')
        return 1
    if not os.path.exists(OPENSSL):
        print('找不到 openssl：%s' % OPENSSL)
        return 1

    opts = parse_args(argv)

    if isinstance(opts.get('check'), str):
        return do_check(opts['check'])

    # --plan 是主人日常用的写法（7d/30d/180d/1y/forever），内部换算成 service + days。
    plan = opts.get('plan')
    if isinstance(plan, str):
        key = PLAN_ALIASES.get(plan.strip(), plan.strip().lower())
        if key not in PLANS:
            print('✗ --plan 不认识：%s' % plan)
            print('  可用：%s' % ' / '.join(PLANS))
            return 1
        opts['service'], opts['days'] = PLANS[key][0], str(PLANS[key][1])

    service = opts.get('service')
    if service not in SERVICES:
        print('--service 必须是 %s 之一' % ' / '.join(SERVICES))
        return 1

    raw_device = opts.get('device')
    if not isinstance(raw_device, str):
        print('✗ 缺少 --device（必填）')
        print('  凭证必须绑定买家设备的码，否则任何人都能用它解锁。')
        return 1

    devices = [normalize_device(part) for part in raw_device.split(',')]
    devices = [d for d in devices if d]
    for code in devices:
        if not DEVICE_RE.match(code):
            print('✗ 设备码不合法：%s（归一化后 %d 位，应为 32 位十六进制）' % (code, len(code)))
            return 1

    batch = int(opts.get('batch', 1)) if isinstance(opts.get('batch'), str) else 1
    if batch > 1 and len(devices) > 1 and len(devices) != batch:
        print('✗ --device 给了 %d 个码，但 --batch 是 %d。' % (len(devices), batch))
        return 1

    default_days = 7 if service == 'trial' else 0
    days = int(opts['days']) if isinstance(opts.get('days'), str) else default_days
    note = opts.get('note')

    for index in range(batch):
        device = devices[0] if len(devices) == 1 else devices[index]
        code = issue(service, device, days, note)
        print(code)
        # 对账信息走 stderr：stdout 只留纯凭证，方便重定向进文件
        if service == 'lifetime':
            validity = '永久'
        elif days % 365 == 0 and days:
            validity = '%d 年' % (days // 365)
        else:
            validity = '%d 天' % days
        print('— %s（%s），绑定 %s，%d 字符'
              % (service, validity, device, len(code)),
              file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
