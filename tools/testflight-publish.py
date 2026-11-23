#!/usr/bin/env python3
"""把刚上传的构建挂进 TestFlight 外部群组，并写好「测试内容」。

为什么需要它：Apple 不会把新构建自动挂到外部测试组——每个构建都要手动
「添加构建版本至群组」，还要逐版填测试内容。这个脚本用 App Store Connect
API 把这两步做成一条命令：

    python3 tools/testflight-publish.py --build 239 \
        --notes-file tools/testflight-notes/1.0.0-239.md

不给 --build 时自动取最近一个处理完成的构建。缺省会：
  1) 挂到外部群组（已挂过则跳过，可重复执行）
  2) 写入（或更新）简体中文的「测试内容」
  3) 没在测试中且未提交过审核时，提交 Beta App 审核（--no-review 可跳过）

凭据：~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
      可用环境变量覆盖：ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH
私钥绝不入库（.gitignore 已忽略 *.p8）。

依赖：只用标准库 + 系统 openssl（用来做 ES256 签名）。
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.jikezhang.codelumi"
EXTERNAL_GROUP_NAME = "Codelumi公测"
LOCALE = "zh-Hans"

KEY_ID = os.environ.get("ASC_KEY_ID", "34Z43R5SGY")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "e2936bfc-e52b-4931-a763-9f03dec868e3")
KEY_PATH = os.environ.get(
    "ASC_KEY_PATH",
    os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"),
)


# ---------------------------------------------------------------- JWT (ES256)

def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _der_to_raw(der: bytes) -> bytes:
    """把 openssl 输出的 DER ECDSA 签名转成 JWT 需要的 r||s（各 32 字节）。"""
    if der[0] != 0x30:
        raise ValueError("unexpected ECDSA DER signature")
    idx = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = []
    for _ in range(2):
        if der[idx] != 0x02:
            raise ValueError("unexpected ECDSA DER integer")
        length = der[idx + 1]
        value = der[idx + 2: idx + 2 + length]
        idx += 2 + length
        value = value.lstrip(b"\x00").rjust(32, b"\x00")
        out.append(value)
    return out[0] + out[1]


def make_token() -> str:
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": ISSUER_ID, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = (
        _b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + _b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", KEY_PATH],
        input=signing_input.encode(),
        capture_output=True,
        check=True,
    ).stdout
    return signing_input + "." + _b64url(_der_to_raw(der))


# ------------------------------------------------------------------ API 调用

def api(method: str, path: str, body: dict | None = None, *, query: dict | None = None):
    url = API + path
    if query:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {make_token()}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")
        raise SystemExit(f"ASC API {method} {path} → HTTP {err.code}\n{detail[:1200]}")


# ------------------------------------------------------------------ 业务步骤

def find_app_id() -> str:
    data = api("GET", "/v1/apps", query={"filter[bundleId]": BUNDLE_ID, "limit": "5"})
    apps = data.get("data", [])
    if not apps:
        raise SystemExit(f"ASC 里找不到 bundleId={BUNDLE_ID} 的 App")
    return apps[0]["id"]


def find_build(app_id: str, build_number: str | None) -> dict:
    data = api(
        "GET",
        f"/v1/apps/{app_id}/builds",
        query={
            # 🔴 ASC 这个接口按**上传时间正序**返回，且不支持 sort —— limit 给 20 时
            #    拿到的是最老的 20 个，新构建永远"找不到"（2026-11-14 踩，287/289 都中招）。
            "limit": "200",
            "fields[builds]": "version,uploadedDate,processingState,expired",
        },
    )
    builds = data.get("data", [])
    # 这个接口不支持 sort，按上传时间在本地倒序
    builds.sort(key=lambda b: b["attributes"].get("uploadedDate") or "", reverse=True)
    if not builds:
        raise SystemExit("这个 App 还没有构建")
    if build_number is None:
        for build in builds:
            if build["attributes"].get("processingState") == "VALID":
                return build
        raise SystemExit("还没有处理完成的构建，稍等几分钟再试")
    for build in builds:
        if build["attributes"]["version"] == str(build_number):
            return build
    raise SystemExit(f"找不到构建 {build_number}；最近的是 "
                     + ", ".join(b["attributes"]["version"] for b in builds))


def find_external_group(app_id: str) -> dict:
    data = api("GET", "/v1/betaGroups", query={
        "filter[app]": app_id,
        "limit": "50",
        "fields[betaGroups]": "name",
    })
    for group in data.get("data", []):
        if group["attributes"].get("isInternal"):
            continue
        if group["attributes"]["name"] == EXTERNAL_GROUP_NAME:
            return group
    names = [g["attributes"]["name"] for g in data.get("data", []) if not g["attributes"].get("isInternal")]
    raise SystemExit(f"找不到外部群组「{EXTERNAL_GROUP_NAME}」；现有外部群组：{names}")


def attached_build_ids(group_id: str) -> set[str]:
    data = api("GET", f"/v1/betaGroups/{group_id}/builds", query={"limit": "50"})
    return {b["id"] for b in data.get("data", [])}


def attach(group_id: str, build_id: str) -> None:
    api("POST", f"/v1/betaGroups/{group_id}/relationships/builds", {
        "data": [{"type": "builds", "id": build_id}]
    })


def upsert_whats_new(build_id: str, notes: str) -> str:
    data = api("GET", f"/v1/builds/{build_id}/betaBuildLocalizations",
               query={"limit": "50"})
    for loc in data.get("data", []):
        if loc["attributes"].get("locale") == LOCALE:
            api("PATCH", f"/v1/betaBuildLocalizations/{loc['id']}", {
                "data": {
                    "type": "betaBuildLocalizations",
                    "id": loc["id"],
                    "attributes": {"whatsNew": notes},
                }
            })
            return "updated"
    api("POST", "/v1/betaBuildLocalizations", {
        "data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": LOCALE, "whatsNew": notes},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }
    })
    return "created"


def review_state(build_id: str) -> str | None:
    """返回 Beta App 审核状态（如 WAITING_FOR_REVIEW / IN_REVIEW / APPROVED），没有则为 None。"""
    try:
        data = api("GET", "/v1/betaAppReviewSubmissions",
                   query={"filter[build]": build_id, "limit": "5"})
    except SystemExit:
        return None
    for item in data.get("data", []):
        state = item["attributes"].get("betaReviewState")
        if state:
            return state
    return None


def submit_for_review(build_id: str) -> str:
    api("POST", "/v1/betaAppReviewSubmissions", {
        "data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }
    })
    return "submitted"


def main() -> int:
    parser = argparse.ArgumentParser(description="把构建挂进 TestFlight 外部群组并写测试内容")
    parser.add_argument("--build", help="构建号（CFBundleVersion），省略则取最近一个处理完成的")
    parser.add_argument("--notes-file", help="测试内容（Markdown/纯文本）路径")
    parser.add_argument("--notes", help="直接给测试内容文本（优先于 --notes-file）")
    parser.add_argument("--no-review", action="store_true", help="不提交 Beta App 审核")
    parser.add_argument("--dry-run", action="store_true", help="只打印将要做什么")
    args = parser.parse_args()

    if not os.path.exists(KEY_PATH):
        raise SystemExit(f"找不到 API 私钥：{KEY_PATH}")
    if not (args.notes_file or args.notes):
        raise SystemExit("必须给 --notes-file 或 --notes（测试内容不能空着）")

    notes = args.notes if args.notes else open(args.notes_file, encoding="utf-8").read()
    notes = notes.strip()
    if len(notes) > 4000:
        raise SystemExit(f"测试内容 {len(notes)} 字，超过 ASC 上限 4000")

    app_id = find_app_id()
    build = find_build(app_id, args.build)
    build_id = build["id"]
    version = build["attributes"]["version"]
    state = build["attributes"].get("processingState")
    print(f"App {app_id} · 构建 {version} ({build_id}) · processingState={state}")

    group = find_external_group(app_id)
    group_id = group["id"]
    print(f"外部群组「{group['attributes']['name']}」({group_id})")

    already = build_id in attached_build_ids(group_id)
    print("挂群组：" + ("已挂过，跳过" if already else "需要添加"))
    if not already and not args.dry_run:
        attach(group_id, build_id)

    print("测试内容：" + ("dry-run 不写" if args.dry_run else upsert_whats_new(build_id, notes)))

    if not args.no_review:
        current = review_state(build_id)
        if current in ("WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"):
            print(f"Beta 审核：{current}，跳过")
        elif args.dry_run:
            print("Beta 审核：dry-run 不提交")
        else:
            print("Beta 审核：" + submit_for_review(build_id))

    print(f"完成：构建 {version} 已挂进「{group['attributes']['name']}」，测试内容 {len(notes)} 字")
    return 0


if __name__ == "__main__":
    sys.exit(main())
