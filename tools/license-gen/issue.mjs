#!/usr/bin/env node
// ============================================================================
// Codelumi · 离线凭证签发工具
//
// 用法：
//   node issue.mjs --service lifetime --device 3F2A…（32 位十六进制）
//   node issue.mjs --service trial    --device 3F2A…            # 临时，默认 7 天
//   node issue.mjs --service lifetime --device 3F2A… --note "订单尾号1234"
//   node issue.mjs --device A,B,C --batch 3 --service lifetime  # 三个买家各一张
//   node issue.mjs --check "CLIP1.xxx.yyy"                     # 只校验，不签发
//
// 输出直接是一串凭证，整段复制发给买家即可。
//
// 🔴 私钥 private-key.pem 与这个目录**永不进仓库、永不进 App 包**。
//    私钥泄露 = 任何人都能自造永久会员，且没有补救手段（除非换公钥，
//    那会让已发出的所有凭证当场作废）。
//
// ── 三个必须做对的细节（改这个文件时务必保持）──────────────────────────
//
// 1) **签名用 P1363，不是默认的 DER。**
//    App 侧走 CryptoKit 的 `P256.Signing.ECDSASignature(rawRepresentation:)`，
//    它要的是 r||s 定长拼接（各 32 字节，共 64 字节）；Node 的 `sign()` 默认
//    吐 DER（带 ASN.1 头、长度可变）。不指定 dsaEncoding 就会**签得出来但验不过**，
//    而且报错信息只会说"校验未通过"，极难定位。
//
// 2) **时间不能带毫秒。**
//    App 侧 JSONDecoder 用 `.iso8601`，它不接受 `2026-09-23T05:00:00.000Z`
//    这种带小数秒的形式，会直接抛解码错误 → 整张凭证被判 malformed。
//    `toISOString()` 默认带毫秒，必须剥掉。
//
// 3) 签名对象是 **`CLIP1.<payload>` 整段**，不是只有 payload。
//    这挡住"把版本前缀改一改"的重放。
//
// ── 设备绑定（--device 必填）────────────────────────────────────────────
//
// 凭证里签进买家的**本机设备码**（App 的「解锁」页会显示，32 位大写 HEX）。
// 一张凭证只在那一台设备上生效 —— 买家转发给别人，别人导进去也解锁不了。
// 这是纯离线体系里唯一能挡「一码多卖」的机制，所以 `--device` 是**必填**：
// 忘了传就是发出去一张全网通用券，而凭证一旦发出就收不回来。
//
// ⚠️ 批量签发：`--device` 支持逗号分隔多个码，与 `--batch` 一一对应；
//    只给一个码而 `--batch > 1` 时，全部绑到同一个码上（补发/续期场景）。
// ============================================================================

import { createPrivateKey, sign as cryptoSign } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const PREFIX = 'CLIP1';
// 2026-10-30：买断制。trial = 临时（7 天），lifetime = 买断（永久，不带到期）。
const SERVICES = ['trial', 'lifetime'];

// ── 参数 ────────────────────────────────────────────────────────────────────

const argv = process.argv.slice(2);
function arg(name, fallback = null) {
  const at = argv.indexOf(`--${name}`);
  if (at === -1) return fallback;
  const next = argv[at + 1];
  return next && !next.startsWith('--') ? next : true;
}

const service = arg('service');
const note = arg('note');
const batch = Number(arg('batch', 1));
const check = arg('check');
const deviceArg = arg('device');

// ── 设备码 ──────────────────────────────────────────────────────────────────
//
// 归一化与 App 侧 `LicenseDevice.normalize` **必须完全一致**：大写、只留十六进制
// 字符。买家发过来的码可能带连字符、空格，或者被聊天软件改过大小写 ——
// 两侧归一化规则不一致，就会变成"卖家说签了、用户说验不过"的经典售后。

const normalizeDevice = (raw) => String(raw).toUpperCase().replace(/[^0-9A-F]/g, '');
const DEVICE_RE = /^[0-9A-F]{32}$/;

/** `--device` 的多个码（按顺序与 batch 对应）；没传时返回空数组 */
function deviceList() {
  if (typeof deviceArg !== 'string') return [];
  return deviceArg.split(',').map(normalizeDevice).filter((s) => s.length > 0);
}

/** 为第 index 张凭证取设备码：多个码按序取，只有一个码则复用 */
function deviceFor(index) {
  const list = deviceList();
  if (list.length === 0) return null;
  return list.length === 1 ? list[0] : (list[index] ?? null);
}

function requireValidDevice() {
  const list = deviceList();
  if (list.length === 0) {
    console.error('✗ 缺少 --device（必填）');
    console.error('');
    console.error('  凭证必须绑定买家设备的码，否则任何人都能用它解锁。');
    console.error('  让买家在 App 的「我的 › 解锁」页复制本机设备码发给你，然后：');
    console.error('');
    console.error('    node issue.mjs --service lifetime --device 3F2A1C…（32 位十六进制）');
    console.error('');
    console.error('  提示：买家发来的码带连字符/空格没关系，这里会自动归一化。');
    process.exit(1);
  }
  for (const code of list) {
    if (!DEVICE_RE.test(code)) {
      console.error(`✗ 设备码不合法：${code}`);
      console.error(`  应当是 32 位十六进制字符（0-9 / A-F），当前归一化后 ${code.length} 位。`);
      console.error('  确认买家复制的是「解锁」页里那串设备码，不是凭证或订单号。');
      process.exit(1);
    }
  }
  if (batch > 1 && list.length > 1 && list.length !== batch) {
    console.error(`✗ --device 给了 ${list.length} 个码，但 --batch 是 ${batch}。`);
    console.error('  两者要么相等（一一对应），要么只给一个码（全部绑同一台设备）。');
    process.exit(1);
  }
}

// ── base64url ───────────────────────────────────────────────────────────────

const b64url = (buf) =>
  buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const fromB64url = (str) =>
  Buffer.from(str.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

// ── 时间：去掉毫秒，否则 App 侧解不出来（见文件头第 2 条）──────────────────

const iso = (date) => date.toISOString().replace(/\.\d{3}Z$/, 'Z');

// ── 私钥 ────────────────────────────────────────────────────────────────────

const keyPath = join(HERE, 'private-key.pem');
if (!existsSync(keyPath)) {
  console.error(`找不到私钥：${keyPath}`);
  console.error('这个文件不进仓库 —— 换机器时记得单独拷过来。');
  process.exit(1);
}
const privateKey = createPrivateKey({ key: readFileSync(keyPath, 'utf8'), format: 'pem' });

// ── 校验模式 ────────────────────────────────────────────────────────────────

if (typeof check === 'string') {
  const parts = check.trim().split('.');
  if (parts.length !== 3 || parts[0] !== PREFIX) {
    console.error('✗ 格式不对：应当是 CLIP1.<payload>.<signature> 三段');
    process.exit(1);
  }
  const signed = Buffer.from(`${parts[0]}.${parts[1]}`);
  const sig = fromB64url(parts[2]);

  const { createPublicKey, verify } = await import('node:crypto');
  const publicKey = createPublicKey(privateKey);
  const ok = verify('sha256', signed, { key: publicKey, dsaEncoding: 'ieee-p1363' }, sig);

  const payload = JSON.parse(fromB64url(parts[1]).toString('utf8'));
  console.log(ok ? '✓ 签名有效' : '✗ 签名无效');
  console.log('  载荷：', JSON.stringify(payload));

  if (payload.d) {
    console.log(`  绑定设备：${payload.d}`);
    console.log('  ⚠️ 这串码只在那台设备上生效 —— 通知买家别把它转发给别人（也没用）。');
  } else {
    console.log('  ⚠️ 这张凭证没有绑定设备（d 字段缺失）—— App 会拒绝导入。');
  }

  if (payload.e) {
    const expired = new Date(payload.e) <= new Date();
    console.log(`  到期：${payload.e}${expired ? '（已过期）' : ''}`);
  } else {
    console.log('  到期：永久');
  }
  process.exit(ok ? 0 : 1);
}

// ── 签发 ────────────────────────────────────────────────────────────────────

if (!SERVICES.includes(service)) {
  console.error(`--service 必须是 ${SERVICES.join(' / ')} 之一`);
  console.error('例：node issue.mjs --service lifetime --device 3F2A…');
  process.exit(1);
}

requireValidDevice();

// 周期默认值：临时档 7 天；买断档不设到期。
// --days 可覆盖（补发延期之类都用它）。
const defaultDays = service === 'trial' ? 7 : 0;
const days = Number(arg('days', defaultDays));

const issuedAt = new Date();

function issue(device) {
  // 字段顺序固定为 s/d/e/i/n：JSON 文本是签名对象的一部分，
  // 顺序变了签名跟着变（不影响正确性，但固定下来便于人工比对与排障）。
  const payload = { s: service, d: device, i: iso(issuedAt) };
  if (service !== 'lifetime') {
    payload.e = iso(new Date(issuedAt.getTime() + days * 86400000));
  }
  if (typeof note === 'string') payload.n = note;

  const payloadB64 = b64url(Buffer.from(JSON.stringify(payload)));
  const signed = Buffer.from(`${PREFIX}.${payloadB64}`);
  const signature = cryptoSign('sha256', signed, {
    key: privateKey,
    dsaEncoding: 'ieee-p1363', // ← 见文件头第 1 条，不可省
  });

  return `${PREFIX}.${payloadB64}.${b64url(signature)}`;
}

if (batch > 1) {
  for (let i = 0; i < batch; i += 1) {
    console.log(issue(deviceFor(i)));
    // 一一对应时，把码一并打到 stderr 便于对账（stdout 只留纯凭证，方便重定向进文件）
    console.error(`  #${i + 1} → ${deviceFor(i)}`);
  }
} else {
  const device = deviceFor(0);
  const code = issue(device);
  console.log(code);
  console.error(`— ${service}${service === 'lifetime' ? '（永久）' : `，${days} 天`}，绑定 ${device}，${code.length} 字符`);
  console.error('  整段复制发给买家；对方在 App 的「VIP 模式 › 导入凭证」里粘贴即可。');
  console.error('  ⚠️ 这张凭证只在上面那台设备上生效 —— 买家转发给别人也解锁不了。');
}
