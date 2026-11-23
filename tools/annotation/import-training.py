#!/usr/bin/env python3
"""把 App 导出的 `codelumi-training.jsonl` 并入标注模板。

用法：
    python3 tools/annotation/import-training.py codelumi-training.jsonl
    # 默认并入 标注模板_定稿.tsv（已有的保持不变，只在末尾追加新样本）
    python3 tools/annotation/import-training.py codelumi-training.jsonl --target 标注模板_定稿.tsv

输入：每行一个 JSON，字段来自 App 的 TrainingSample：
    {text, label, code?, address?, note?, createdAt, appVersion, osVersion, machine}

行为：
    · 按「删空白后全等」去重（与 gen-template 同口径），已有原文直接跳过；
    · 追加行的「预填」列留空，人工列填 App 里用户给的值；
    · 输出统计：新增多少、跳过多少重复。
"""
import json
import re
import sys
import csv
from pathlib import Path

src = Path(sys.argv[1] if len(sys.argv) > 1 else "codelumi-training.jsonl")
target = Path("标注模板_定稿.tsv")
if "--target" in sys.argv:
    target = Path(sys.argv[sys.argv.index("--target") + 1])

HEADER = ["序号", "预填判定", "预填取件码", "运单号", "尾号", "快递公司", "预填地址",
          "货架", "柜位", "原文", "人工判定(pickup/other)", "人工取件码",
          "人工地址", "人工备注/驿站"]

def norm(s: str) -> str:
    return re.sub(r"\s+", "", s or "")

rows = []
if target.exists():
    rows = [r for r in target.read_text(encoding="utf-8").splitlines() if r.strip()]
    rows = [r.split("\t") for r in rows]
    if not rows or rows[0][0] != "序号":
        rows = [HEADER] + rows
else:
    rows = [HEADER]

seen = {norm(r[9]) for r in rows[1:] if len(r) > 9}
next_no = max([int(r[0]) for r in rows[1:] if r and r[0].isdigit()] or [0]) + 1

added = skipped = 0
for line in src.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        item = json.loads(line)
    except json.JSONDecodeError:
        skipped += 1
        continue
    text = (item.get("text") or "").strip()
    label = (item.get("label") or "").strip()
    if not text or label not in ("pickup", "other"):
        skipped += 1
        continue
    key = norm(text)
    if key in seen:
        skipped += 1
        continue
    seen.add(key)
    station = (item.get("note") or "").strip()
    rows.append([str(next_no), "", "", "", "", "", "", "", "", text,
                 label, item.get("code") or "", item.get("address") or "", station])
    next_no += 1
    added += 1

with target.open("w", encoding="utf-8", newline="") as f:
    w = csv.writer(f, delimiter="\t", lineterminator="\n")
    w.writerows(rows)

total = len(rows) - 1
pickup = sum(1 for r in rows[1:] if len(r) > 10 and r[10] == "pickup")
print(f"并入 {src.name}：新增 {added}，跳过 {skipped}")
print(f"{target.name} 现有 {total} 条（pickup {pickup} / other {total - pickup}）")
print("下一步：/tmp/retrain " + str(target))
