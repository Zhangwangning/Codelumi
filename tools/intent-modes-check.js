#!/usr/bin/env node
//
// 快捷指令动作口径自检（改完 PickupIntents.swift 后必跑）
//
// 校验两件事，都是「运行时显示 / 不切前台」这条产品口径的机械证据：
//
//  ① 运行模式：所有 App Intent 必须是 supportedModes = 1（仅 .background）
//     且 openAppWhenRun = false —— 自动化触发时 App 不会被拉到前台。
//     ⚠️ rawValue 真值（实测 macOS/iOS 26+ AppIntents）：
//        .background = 1   .foreground = 2   .foreground(.immediate) = 2
//        .foreground(.deferred) = 4          .foreground(.dynamic) = 8
//
//  ② 输出能力：对外的两个动作（ParsePickupTextIntent / ParsePickupImageIntent）
//     必须 outputFlags = 0（不返回 dialog / value / snippet）。
//     Shortcuts 只在意图"有东西可展示"时才给动作配「运行时显示」开关，
//     所以不产出结果是让该开关无从生效的唯一手段 —— 详见 PickupIntents.swift 文件头。
//
// 用法：
//   node tools/intent-modes-check.js                       # 用默认 DerivedData 路径
//   APP_PATH=/path/to/Codelumi.app node tools/intent-modes-check.js

const fs = require("fs");
const path = require("path");

const DEFAULT_DD = "/tmp/codelumi-dd";
const appPath =
  process.env.APP_PATH ||
  path.join(DEFAULT_DD, "Build/Products/Debug-iphonesimulator/Codelumi.app");

const actionsPath = path.join(appPath, "Metadata.appintents/extract.actionsdata");

if (!fs.existsSync(actionsPath)) {
  console.error(`❌ 找不到元数据：${actionsPath}`);
  console.error("   先构建一次，或用 APP_PATH=... 指定 .app 路径。");
  process.exit(2);
}

const MODE_NAMES = {
  1: ".background",
  2: ".foreground(.immediate)",
  3: "[.background, .foreground]",
  4: ".foreground(.deferred)",
  8: ".foreground(.dynamic)",
  9: "[.background, .foreground(.dynamic)]",
};

/** 允许出现在「快捷指令」动作库里的对外动作 —— 必须无输出 */
const PUBLIC_INTENTS = new Set([
  "ParsePickupTextIntent",
  "ParsePickupImageIntent",
]);

const data = JSON.parse(fs.readFileSync(actionsPath, "utf8"));
const actions = data.actions || {};

let failures = 0;
const rows = [];

for (const name of Object.keys(actions).sort()) {
  const a = actions[name];
  const modes = a.supportedModes;
  const openApp = a.openAppWhenRun;
  const flags = a.outputFlags;
  const isPublic = PUBLIC_INTENTS.has(name);

  const problems = [];
  if (modes !== 1) {
    problems.push(`supportedModes=${modes} (${MODE_NAMES[modes] || "未知"})，必须为 1 (.background)`);
  }
  if (openApp !== false) {
    problems.push(`openAppWhenRun=${openApp}，必须为 false`);
  }
  if (isPublic && flags !== 0) {
    problems.push(`outputFlags=${flags}，对外动作必须为 0（否则快捷指令会给出「运行时显示」开关）`);
  }
  if (problems.length) failures++;

  rows.push({
    name,
    modes: `${modes} ${MODE_NAMES[modes] || ""}`.trim(),
    openApp: String(openApp),
    flags: String(flags),
    scope: isPublic ? "对外" : "内部",
    ok: problems.length === 0,
    problems,
  });
}

const pad = (s, n) => s + " ".repeat(Math.max(0, n - [...s].reduce((w, c) => w + (c.charCodeAt(0) > 0x2e80 ? 2 : 1), 0)));

console.log(`元数据：${actionsPath}\n`);
console.log(`${pad("动作", 26)}${pad("支持模式", 26)}${pad("openAppWhenRun", 16)}${pad("outputFlags", 13)}范围`);
console.log("-".repeat(96));
for (const r of rows) {
  console.log(
    `${r.ok ? "  " : "❌"}${pad(r.name, 24)}${pad(r.modes, 26)}${pad(r.openApp, 16)}${pad(r.flags, 13)}${r.scope}`
  );
}

if (failures) {
  console.log("");
  for (const r of rows.filter((x) => !x.ok)) {
    console.log(`❌ ${r.name}`);
    for (const p of r.problems) console.log(`     · ${p}`);
  }
  console.log(`\n共 ${failures} 个动作口径不符。`);
  process.exit(1);
}

console.log(
  "\n✅ 全部动作均为 .background（不切前台、不打开 App），对外动作无输出（快捷指令不会提供「运行时显示」开关）"
);
