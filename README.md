# Codelumi

**English** · [简体中文](README.zh-CN.md)

An iOS app that collects parcel pickup codes out of SMS. Everything stays on your
device: no network calls, nothing uploaded, no account.

---

## Project

| | |
|---|---|
| Name | Codelumi / 珞米 (1.0.0, build 325) |
| Platform | iOS 17 and later (iPhone; iPhone Duo foldable has its own layout work) |
| Project | Plain Xcode project, SwiftUI, no SPM packages, no third-party libraries |
| Layout | repository root `Codelumi/` → project root `Codelumi/` → `Codelumi/` (app), `CodelumiShared/` (shared with the widget), `CodelumiWidget/` (widget extension) |
| Status | In TestFlight beta; the App Store version is in the review pipeline |

The user-facing name is **Codelumi** (Chinese: 珞米). Every identifier now matches it:
bundle ID `com.jikezhang.codelumi`, App Group `group.com.jikezhang.codelumi`, iCloud
container `iCloud.com.jikezhang.codelumi`, widget extension `CodelumiWidget`, repository
and Xcode project `Codelumi`. The rename history is 拾码 (the shortcut) → Allude (the
working name of the first builds) → Codelumi.

Codelumi is a standalone, offline tool. Its feature set comes from the author's own
open-source Shortcuts project and from parcel-pickup workflows in daily use — it does
not take features or interface from other apps.

## Where the idea came from: a shortcut first

This app did not start as a product idea. It started as a Shortcuts action.

Several parcel SMS arrive every day, the pickup codes are scattered across them,
and getting a parcel means scrolling back through Messages and retyping a code at
the locker. So the first version was a shortcut called 「快递取件码」 (parcel pickup
code): a few regular expressions that pulled the code out of the SMS, formatted it,
and put it on the clipboard or into Notes. Multiple codes per message, the pickup
point name and the address were added later.

That shortcut lives in
[shortcut_pickup_code](https://gitee.com/zhang_wangning/shortcut_pickup_code)
(Gitee mirror; the GitHub copy is being published).

Once it circulated a little, the feedback was consistent:

- screenshots had to be saved by hand, and were still lost afterwards;
- people wanted "already picked up" separated from "still waiting";
- people wanted the codes on the home screen instead of opening something;
- people wanted a reminder when they arrived at the pickup point;
- a message with two codes was not split cleanly.

That feedback says one thing: **collecting pickup codes from SMS is a real need**,
not an invented feature. But a shortcut has a ceiling: no list, no search, no
grouping or sorting, no reminders or widget, one more "automation ran" notification
per execution, and the rules hard-coded inside a single action.

So the parsing rules were moved into a native app — that is Codelumi. The shortcut
project and its corpus are still part of this repository, and the app's parser grew
directly out of them: four regular-expression families, the same priority chain,
the same field conventions, then extended rule by rule against real messages.

## What it does

- Pulls the pickup code out of an SMS or a screenshot, together with courier,
  pickup point, address, locker and shelf, into one record
- Two lists — waiting and picked up — groupable and sortable by time, courier or
  pickup point
- A home-screen widget and a Live Activity show the latest codes without opening the app
- Optional arrival reminder when you reach the pickup point (location permission is
  only requested if you turn it on)
- Statistics, search, batch marking as picked up, sharing a code

## How it works

**1. How the message gets in**

Three routes, the user picks one:

- On iOS 27, import a "when I receive a message containing X → add to Codelumi"
  automation in one step (older systems: build one by hand, there is a tutorial in the app)
- Screenshot intake: pick an image, read the text
- Paste the whole SMS manually

**2. How it parses**

Rules first. Four independent regular-expression families behind a priority chain
(pickup code → waybill number → last digits → special formats), and each message is
matched against the first family that hits.

When one message contains several codes, they are split into several cards, but the
segments must keep the same shape as the first one — otherwise a locker number gets
mistaken for a second code.

Fields produced: pickup code, courier, pickup point, address, locker / shelf.

Pickup-point names are matched only against the catalogue's `name` and `aliases`,
**never the short key** — scanning message bodies with something like "中邮" turns
"中邮大厦" into a pickup point. Users can add their own pickup points, and those
participate in matching immediately.

**3. How pickup points are grouped**

A pickup point can be assigned to a group. A group is a place: it has its own name,
icon and location. A pickup point belongs to one group only; individual records that
were collected somewhere else can be assigned in the detail page. Ordering across the
waiting list, the picked-up list and the widget is the same everywhere: most records
first, ties by name, and "no pickup point" last.

**4. Where data lives**

A JSON file under `Application Support` on the device. There is a record cap; when
it is exceeded the oldest records are dropped first — and only while a new message
is being ingested, never on launch.

iCloud sync is optional: records are written into **your own** iCloud Drive
(`Documents/Codelumi/records.json`), never through a developer server. Merging happens
per record — the newer `updatedAt` wins — and deletions leave tombstones so another
device does not resurrect them.

**5. On-device intelligence only fills gaps**

If the rules miss a field, Apple's on-device model is asked to fill that one gap.
Everything else is decided by rules, and the model may **only fill, never overwrite**
— in particular it never touches a pickup code that was already found. When the model
is unavailable (common on devices sold in mainland China) the parser simply runs on
rules alone.

## Safety baseline

This is the part the project cares about most: **the app has no reason to send data
out, and no channel to do it through.**

- No developer server, no domain, no third-party SDK, no API key
- No networking code. Verify it yourself:

```bash
grep -rn "URLSession\|URLRequest\|NSURLConnection" Codelumi/Codelumi Codelumi/CodelumiShared Codelumi/CodelumiWidget
# no output
```

- The only two things touching the network belong to Apple: iCloud sync (off by
  default, into your own container) and App Store capabilities
- The diagnostics log records what happened — version, OS, message length and record
  count, error codes, timings. It never records message text, pickup codes,
  addresses, phone numbers or device identifiers
- There are no accounts, so there is no "forgot password" and no "sync to our cloud"

## Build

```bash
cd Codelumi
xcodebuild -project Codelumi.xcodeproj -scheme Codelumi \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/codelumi-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```

`-disable-sandbox` exists so the macro plugin (`swift-plugin-server`) can spawn its
helper process. With the build process sandboxed you get a pile of bogus errors
(typically `'self' is immutable` in `SwipeActionRow.swift`) — a toolchain problem,
not something to fix in app code.

## What's in the repository (development history)

| File | Contents |
|---|---|
| `AGENTS.md` | Project instructions: hard rules, layout, type scale, icon specs, release pipeline, module conventions |
| `交接说明_dsh.md` | Full handover document: measured status, three-level layout, file map by importance, known issues |
| `交接说明_workbuddy.md` | An earlier handover record |
| `快递短信解析规格_V803.md` | Parser spec: priority chain, mis-parse gates, field conventions |
| `短信语料库_v1.md` | 514 real parcel SMS segments (anonymized), used as the regression corpus |
| `iPhone Duo 适配规范_v1.md`, `iPhone Duo 官方设计规范笔记_v1.md` | Foldable design notes and an Apple Tech Talks summary |
| `产品与商业模式规格_v1.md` | Early product scope (historical document) |
| `.workbuddy/memory/*.md` | Day-by-day log: decisions, mistakes, and why things were reverted |
| `tools/` | Self-check harnesses: parser regression, pickup-point matching, brand table, dedupe, OCR pipeline, unit assertions |

Every harness's `main.swift` header lists its full compile command. For example:

```bash
swiftc -O -o /tmp/parser-regression \
  Codelumi/Codelumi/Models/PickupParser.swift tools/parser-regression/main.swift && \
/tmp/parser-regression 短信语料库_v1.md
# current baseline: 193/514 codes, 192/514 addresses
```

## Credits

极客ZHANG · zhang_wangning@126.com

Third-party marks (courier and pickup-point logos) are used only to identify where a
parcel is waiting. Copyright remains with each brand; no partnership or endorsement
is implied.
