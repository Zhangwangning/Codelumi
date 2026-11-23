#!/usr/bin/env python3
"""把 TestFlight 里「低于指定构建号」的历史构建设为过期（停止测试）。

    python3 tools/asc-expire-old-builds.py --below 325          # 演练：只列出会动谁
    python3 tools/asc-expire-old-builds.py --below 325 --apply  # 真删

Apple 的语义：PATCH /v1/builds/{id} 的 `expired=true` =
「停止测试」——测试者不再能安装它，但构建本身与它的历史记录都还在，
不是删除。已经在跑这个版本的测试者不会被打断，只是不能再新装。

只处理同一条版本线（默认 1.0.0）的构建，避免误伤别的版本。
凭据复用 tools/testflight-publish.py 里的 JWT / api 实现。
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tfp", os.path.join(HERE, "testflight-publish.py"))
tfp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tfp)

ap = argparse.ArgumentParser()
ap.add_argument("--below", type=int, required=True, help="低于这个构建号的都停测")
ap.add_argument("--app-version", default="1.0.0", help="只处理这条版本线，默认 1.0.0")
ap.add_argument("--apply", action="store_true", help="真的执行；不给只演练")
args = ap.parse_args()

app = tfp.api("GET", "/v1/apps", query={"filter[bundleId]": "com.jikezhang.codelumi"})
if "data" not in app or not app["data"]:
    print("找不到 App:", json.dumps(app, ensure_ascii=False)[:300])
    sys.exit(1)
aid = app["data"][0]["id"]

builds: list[dict] = []
url = "/v1/builds"
query = {
    "filter[app]": aid,
    "filter[preReleaseVersion.version]": args.app_version,
    "limit": "200",
    "fields[builds]": "version,expired,processingState,uploadedDate",
}
while url:
    r = tfp.api("GET", url, query=query)
    if "data" not in r:
        print("查询失败:", json.dumps(r, ensure_ascii=False)[:300])
        sys.exit(1)
    builds.extend(r["data"])
    url = (r.get("links") or {}).get("next")
    query = None  # next 里已带全参

targets = []
for b in builds:
    a = b["attributes"]
    try:
        ver = int(a["version"])
    except (TypeError, ValueError):
        continue
    if ver < args.below and not a.get("expired"):
        targets.append((ver, b["id"], a.get("expired")))

targets.sort(key=lambda x: -x[0])
if not targets:
    print(f"没有需要停测的构建（{args.app_version} 下低于 {args.below} 的全部已过期/不存在）")
    sys.exit(0)

print(f"共 {len(targets)} 个构建将停止测试：")
for ver, bid, _ in targets:
    print(f"  构建 {ver:>4}  id={bid}")

if not args.apply:
    print("\n这是演练。加 --apply 才会真的执行。")
    sys.exit(0)

ok = fail = 0
for ver, bid, _ in targets:
    r = tfp.api("PATCH", f"/v1/builds/{bid}", body={
        "data": {"type": "builds", "id": bid, "attributes": {"expired": True}}
    })
    if "data" in r and r["data"]["attributes"].get("expired"):
        print(f"  ✓ 构建 {ver} 已停止测试")
        ok += 1
    else:
        print(f"  ✗ 构建 {ver} 失败: {json.dumps(r, ensure_ascii=False)[:200]}")
        fail += 1

print(f"\n完成：成功 {ok}，失败 {fail}")
sys.exit(0 if fail == 0 else 1)
