import Foundation
import CryptoKit

// ============================================================================
// 凭证核心：签发 / 验签 / 台账
//
// 与 tools/license-gen/issue.mjs、CodelumiShared/OfflineLicense.swift 三者
// **必须字节一致**，否则「卖家说签了、买家说验不过」。四处细节：
//   ① payload JSON 字段顺序固定 s→d→i→e→n，中间不能有空格
//   ② 载荷编码用 base64url（+→-  /→_  去掉 =）
//   ③ 签名对象是 "CLIP1.<载荷>" 整段
//   ④ 签名是 ECDSA P-256 / SHA-256 / P1363（64 字节）
// 本实现走 CryptoKit —— 与 iOS App 侧同一个框架，第 ④ 条天然对齐。
// ============================================================================

/// 凭证档位。2026-10-30 改买断制：只保留临时（7 天）与买断（永久）。
/// 🔴 必须与 App 侧 `CodelumiShared/OfflineLicense.swift` 的 `LicenseService` 完全一致 ——
///    多一个 case，签出来的凭证在 App 里会解不出枚举，直接判 `malformed`。
enum LicenseService: String, CaseIterable {
    case trial, lifetime

    var title: String {
        switch self {
        case .trial: return "临时"
        case .lifetime: return "买断"
        }
    }

    var defaultDays: Int {
        switch self {
        case .trial: return 7
        case .lifetime: return 0
        }
    }

    func ledgerTitle(days: Int) -> String {
        self == .lifetime ? "永久" : "临时（\(days) 天）"
    }
}

struct IssuedLicense {
    let code: String
    let device: String
    let service: LicenseService
    let days: Int
    let issuedAt: Date
    let expiresAt: Date?
    let note: String?
}

struct VerifiedLicense {
    var valid = false
    var service: String?
    var device: String?
    var issuedAtText: String?
    var expiresAtText: String?
    var note: String?
    var expired = false
    var failure: String?

    var isLifetime: Bool { expiresAtText == nil }

    static func malformed(_ reason: String) -> VerifiedLicense {
        var result = VerifiedLicense()
        result.failure = reason
        return result
    }
}

struct LedgerRow {
    var index: Int
    var issuedAtText: String
    var serviceText: String
    var expiresText: String
    var device: String
    var note: String
    var code: String?
}

enum LicenseError: LocalizedError {
    case invalidDevice(String)
    case keyMissing(String)
    case keyUnreadable(String)
    case ledgerWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidDevice(let detail): return "设备码不合法：\(detail)"
        case .keyMissing(let path): return "找不到私钥：\(path)"
        case .keyUnreadable(let detail): return "私钥读取失败：\(detail)"
        case .ledgerWriteFailed(let detail): return "台账写入失败：\(detail)"
        }
    }
}

// MARK: -

final class LicenseCore {

    static let shared = LicenseCore()

    // MARK: 位置
    //
    // 🔴 为什么读写只落本机容器、不直接读写仓库目录：
    //
    //    仓库位于 /Volumes/<外挂卷> 上。实测（macOS 27.2，noowners 挂载的 APFS 外挂盘）：
    //    一个由 `open` 启动的 App 读该卷上的文件，stat() 0ms 返回 true，
    //    但紧接着的 open() 会在内核里**永久挂起**且不弹任何授权框。
    //    对照实验：同一进程、同一时刻读 /tmp 的文件用 1ms，读外挂卷永久阻塞。
    //    终端里直接执行同一个二进制却正常 —— 因为进程继承了终端的磁盘权限。
    //
    //    后果：只要 UI 构建路径上同步读一次外挂卷，主线程就死在 open()，
    //    窗口永远上不了屏（表现为「双击打开没反应」）。
    //
    //    因此：**工作数据一律放本机 Application Support**，仓库目录仅作导入来源，
    //    且读来源目录只在后台线程做（见 importFromSource）。

    /// 工作目录：App 私有容器，所有日常读写只落这里（本机卷，无门禁）
    static var workspaceDir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("CodelumiIssuer", isDirectory: true)
    }

    /// 私钥与台账的实际读写位置（本机容器内）
    var keyURL: URL { LicenseCore.workspaceDir.appendingPathComponent("private-key.pem") }
    var ledgerURL: URL { LicenseCore.workspaceDir.appendingPathComponent("issued-ledger.md") }

    /// 导入来源目录（仓库里的 tools/license-gen）。只读，且只在后台线程触碰。
    private(set) var sourceDir: URL

    private static let sourceDefaultsKey = "LicenseGenSourceDir"

    private init() {
        // 只做两件安全的事：纯路径推算 + 建本机目录。绝不 stat 外挂卷。
        sourceDir = LicenseCore.guessSourceDir()
        try? FileManager.default.createDirectory(at: LicenseCore.workspaceDir,
                                                 withIntermediateDirectories: true)
    }

    /// 纯路径推算，不做任何 IO（IO 一律交给后台线程）
    private static func guessSourceDir() -> URL {
        if let saved = UserDefaults.standard.string(forKey: sourceDefaultsKey), !saved.isEmpty {
            return URL(fileURLWithPath: saved)
        }
        // 默认布局：tools/license-gen/macapp/build/<App>.app → 上溯三级即 license-gen
        var candidate = Bundle.main.bundleURL
        for _ in 0..<3 { candidate = candidate.deletingLastPathComponent() }
        return candidate
    }

    func setSourceDir(_ url: URL) {
        sourceDir = url
        UserDefaults.standard.set(url.path, forKey: LicenseCore.sourceDefaultsKey)
    }

    /// 私钥是否已就位（查本机容器，安全）
    var keyExists: Bool { FileManager.default.fileExists(atPath: keyURL.path) }

    // MARK: 工作区导入

    enum ImportOutcome {
        case alreadyReady                       // 容器里已有私钥，无需导入
        case imported([String])                 // 成功导入的条目
        case failed(String)                     // 明确失败（如来源里没这个文件）
        case timedOut                           // 跨卷读被系统门禁挂起，需手动导入
    }

    /// 后台把来源目录里的私钥/台账导入本机容器。
    ///
    /// ⚠️ 必须在后台 + 看门狗：读外挂卷可能被内核永久挂起，主线程一旦踩上就卡死。
    ///    主线程用 3 秒看门狗兜底，超时即判定「被门禁拦下」，转手动导入。
    func importFromSource(completion: @escaping (ImportOutcome) -> Void) {
        guard !keyExists else {
            completion(.alreadyReady)
            return
        }

        let source = sourceDir
        var delivered = false
        let lock = NSLock()

        func deliver(_ outcome: ImportOutcome) {
            lock.lock()
            let isFirst = !delivered
            delivered = true
            lock.unlock()
            guard isFirst else { return }
            DispatchQueue.main.async { completion(outcome) }
        }

        // 看门狗：跨卷 open() 被挂起时不会抛错、不会返回，只能靠超时判定
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { deliver(.timedOut) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let keySource = source.appendingPathComponent("private-key.pem")

            guard fm.fileExists(atPath: keySource.path) else {
                deliver(.failed("来源目录里没有 private-key.pem：\(source.path)"))
                return
            }
            do {
                // ↓ 这一行若来源在外挂卷且未授权，会永久阻塞 —— 所以它在后台线程里
                let pem = try String(contentsOf: keySource, encoding: .utf8)
                _ = try P256.Signing.PrivateKey(pemRepresentation: pem)   // 先验格式
                try self.writeKeyFile(pem)

                var imported = ["私钥"]
                let ledgerSource = source.appendingPathComponent("issued-ledger.md")
                if !fm.fileExists(atPath: self.ledgerURL.path),
                   let text = try? String(contentsOf: ledgerSource, encoding: .utf8) {
                    try? text.write(to: self.ledgerURL, atomically: true, encoding: .utf8)
                    imported.append("台账")
                }
                deliver(.imported(imported))
            } catch {
                deliver(.failed(error.localizedDescription))
            }
        }
    }

    /// 用户在文件选择器里选中的私钥文件导入（系统已授权该文件，可读）
    func importKey(from url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let pem = try String(contentsOf: url, encoding: .utf8)
                _ = try P256.Signing.PrivateKey(pemRepresentation: pem)
                try self.writeKeyFile(pem)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func writeKeyFile(_ pem: String) throws {
        // 🔴 私钥落地必须是 0600、目录 0700（2026-10-31 审查修）。
        //    默认 umask 会写成 0644 —— 同机任何账号都能读，等于没有保护。
        try FileManager.default.createDirectory(at: LicenseCore.workspaceDir,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try pem.write(to: keyURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: keyURL.path)
        privateKey = nil
    }

    /// 把容器里的台账写回来源目录（跨卷写，仍在后台线程做，失败静默）
    func exportLedgerToSource(completion: @escaping (Bool) -> Void) {
        let source = sourceDir
        guard let text = try? String(contentsOf: ledgerURL, encoding: .utf8) else {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let target = source.appendingPathComponent("issued-ledger.md")
            do {
                try text.write(to: target, atomically: true, encoding: .utf8)
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // MARK: 密钥

    private var privateKey: P256.Signing.PrivateKey?

    func loadKey() throws -> P256.Signing.PrivateKey {
        if let privateKey { return privateKey }
        guard keyExists else { throw LicenseError.keyMissing(keyURL.path) }
        do {
            let pem = try String(contentsOf: keyURL, encoding: .utf8)
            let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
            privateKey = key
            return key
        } catch {
            throw LicenseError.keyUnreadable(error.localizedDescription)
        }
    }

    var publicKeyBase64: String? {
        (try? loadKey())?.publicKey.rawRepresentation.base64EncodedString()
    }

    // MARK: 时间

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]      // 关键：不带小数秒
        return f
    }()

    private let ledgerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    func isoString(_ date: Date) -> String { isoFormatter.string(from: date) }
    func parseISO(_ text: String) -> Date? { isoFormatter.date(from: text) }
    func ledgerDateString(_ date: Date) -> String { ledgerFormatter.string(from: date) }
    func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: 编码工具

    static func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromB64url(_ text: String) -> Data? {
        var t = text.replacingOccurrences(of: "-", with: "+")
                     .replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    /// 与 App 侧 `LicenseDevice.normalize` / issue.mjs 完全一致：大写 + 只留 0-9A-F
    static func normalizeDevice(_ raw: String) -> String {
        raw.uppercased().filter { $0.isHexDigit }
    }

    static func isValidDevice(_ code: String) -> Bool {
        code.count == 32 && code.allSatisfy { $0.isHexDigit }
    }

    private static func escapeJSON(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    // MARK: 签发

    func issue(rawDevice: String,
               service: LicenseService,
               days: Int,
               note: String?) throws -> IssuedLicense {

        let device = LicenseCore.normalizeDevice(rawDevice)
        guard LicenseCore.isValidDevice(device) else {
            throw LicenseError.invalidDevice("归一化后是 \(device.count) 位，应为 32 位十六进制")
        }

        let key = try loadKey()
        let now = Date()
        let effectiveDays = service == .lifetime ? 0 : max(1, days)
        let expires = service == .lifetime ? nil : now.addingTimeInterval(Double(effectiveDays) * 86400)

        // 手工拼 JSON：顺序固定 s→d→i→e→n，且无空格。
        // 不能用 JSONSerialization —— 它不保证键顺序，而键顺序是签名对象的一部分。
        var pairs: [(String, String)] = [
            ("s", service.rawValue),
            ("d", device),
            ("i", isoFormatter.string(from: now)),
        ]
        if let expires { pairs.append(("e", isoFormatter.string(from: expires))) }
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pairs.append(("n", note))
        }

        let payloadJSON = "{" + pairs
            .map { "\"\($0.0)\":\"\(LicenseCore.escapeJSON($0.1))\"" }
            .joined(separator: ",") + "}"

        let payloadB64 = LicenseCore.b64url(Data(payloadJSON.utf8))
        let signed = Data("CLIP1.\(payloadB64)".utf8)
        let signature = try key.signature(for: signed)
        let code = "CLIP1.\(payloadB64).\(LicenseCore.b64url(signature.rawRepresentation))"

        return IssuedLicense(code: code,
                             device: device,
                             service: service,
                             days: effectiveDays,
                             issuedAt: now,
                             expiresAt: expires,
                             note: note)
    }

    // MARK: 验签

    func verify(_ rawCode: String) -> VerifiedLicense {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return .malformed("没有内容") }

        let parts = code.components(separatedBy: ".")
        guard parts.count == 3 else {
            return .malformed("应当是 CLIP1.<载荷>.<签名> 三段（当前 \(parts.count) 段）——复制时可能漏了尾段或混进换行/空格")
        }
        guard parts[0] == "CLIP1" else { return .malformed("版本前缀不是 CLIP1") }
        guard let payloadData = LicenseCore.fromB64url(parts[1]) else { return .malformed("载荷不是合法的 base64url") }
        guard let sigData = LicenseCore.fromB64url(parts[2]) else { return .malformed("签名不是合法的 base64url") }
        guard sigData.count == 64 else { return .malformed("签名长度 \(sigData.count) 字节，应为 64（P1363）") }

        var result = VerifiedLicense()

        guard let payload = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] else {
            return .malformed("载荷不是合法 JSON")
        }
        result.service = payload["s"] as? String
        result.device = payload["d"] as? String
        result.issuedAtText = payload["i"] as? String
        result.expiresAtText = payload["e"] as? String
        result.note = payload["n"] as? String

        guard let key = try? loadKey() else {
            result.failure = "本机没有私钥，无法验签（\(keyURL.path)）"
            return result
        }

        guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: sigData) else {
            result.failure = "签名格式不合法"
            return result
        }

        let signed = Data("\(parts[0]).\(parts[1])".utf8)
        result.valid = key.publicKey.isValidSignature(signature, for: signed)
        if !result.valid { result.failure = "签名校验未通过（这张码不是本店签的，或被改过）" }

        if let expiresText = result.expiresAtText, let expires = parseISO(expiresText) {
            result.expired = expires <= Date()
        }
        return result
    }

    // MARK: 台账

    private static let ledgerHeader = """
    # Codelumi · 凭证签发台账

    卖家侧对账用（依据 `README.md` 第 112 行：「每单存一份设备码 + 签发记录」）。

    - **每签一张追加一行**，不要回改历史行。
    - **含买家设备码，属隐私数据，不进仓库**（`.gitignore` 已挡）。
    - 售后「码不能用」时的定位顺序：先 `node issue.mjs --check "<用户手上那张>"`，
      再与本表比对**设备码**与**到期日** —— 基本一眼定位。

    ---

    ## 签发记录

    | # | 签发时间（本地） | 档位 | 到期日 | 设备码 | 备注 |
    |---|---|---|---|---|---|
    """

    private static let ledgerTail = """


    ---

    ## 凭证全文

    留底的作用：买家说「码丢了 / 找不到那条消息」时，**原样重发同一张**，
    避免同一设备出现多张到期日不一致的凭证。
    """

    func ledgerText() -> String {
        if let text = try? String(contentsOf: ledgerURL, encoding: .utf8) { return text }
        return LicenseCore.ledgerHeader + LicenseCore.ledgerTail + "\n"
    }

    /// 解析台账表格行（供界面显示）
    func loadLedger() -> [LedgerRow] {
        let text = ledgerText()
        var rows: [LedgerRow] = []
        var codeByIndex: [Int: String] = [:]

        // 凭证全文区块：### 0003 · 设备 `XXX` · 月付 · 至 2026-10-24  后面跟一个 ``` 块
        let blocks = text.components(separatedBy: "\n### ")
        for block in blocks.dropFirst() {
            guard let firstLine = block.components(separatedBy: "\n").first,
                  let numberPart = firstLine.split(separator: " ").first,
                  let index = Int(numberPart) else { continue }
            if let fenceStart = block.range(of: "```"),
               let fenceEnd = block.range(of: "```", range: fenceStart.upperBound..<block.endIndex) {
                let code = String(block[fenceStart.upperBound..<fenceEnd.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty { codeByIndex[index] = code }
            }
        }

        // 表格行：以 | 开头，首列是纯数字
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { continue }
            let cells = trimmed
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 7 else { continue }
            let first = cells[1]
            guard let index = Int(first) else { continue }
            rows.append(LedgerRow(index: index,
                                  issuedAtText: cells[2],
                                  serviceText: cells[3],
                                  expiresText: cells[4],
                                  device: cells[5].replacingOccurrences(of: "`", with: ""),
                                  note: cells[6],
                                  code: codeByIndex[index]))
        }
        return rows.sorted { $0.index < $1.index }
    }

    /// 追加一条签发记录：先补表格行，再补凭证全文块
    @discardableResult
    func appendLedger(_ license: IssuedLicense) throws -> Int {
        var text = ledgerText()

        let existing = loadLedger()
        let index = (existing.map(\.index).max() ?? 0) + 1
        let serial = String(format: "%04d", index)

        let expiresText = license.expiresAt.map { dayString($0) } ?? "永久"
        let noteText = (license.note?.isEmpty == false) ? license.note! : "—"
        let row = "| \(serial) | \(ledgerDateString(license.issuedAt)) | "
            + "\(license.service.ledgerTitle(days: license.days)) | \(expiresText) | "
            + "`\(license.device)` | \(noteText) |"

        // ① 表格行：插在「## 凭证全文」区块之前
        let tableAnchor = "\n\n---\n\n## 凭证全文"
        if let range = text.range(of: tableAnchor) {
            text.replaceSubrange(range, with: "\n\(row)" + tableAnchor)
        } else if let range = text.range(of: "\n---\n\n## 凭证全文") {
            text.replaceSubrange(range, with: "\n\(row)" + "\n---\n\n## 凭证全文")
        } else {
            text += "\n" + row + "\n"
        }

        // ② 凭证全文块
        let expiresLine = license.expiresAt.map { "至 \(dayString($0))" } ?? "永久有效"
        let block = """


        ### \(serial) · 设备 `\(license.device)` · \(license.service.ledgerTitle(days: license.days)) · \(expiresLine)

        ```
        \(license.code)
        ```
        """

        if let range = text.range(of: "\n---\n\n## 到期巡检") {
            text.replaceSubrange(range, with: block + "\n\n---\n\n## 到期巡检")
        } else {
            text += block + "\n"
        }

        do {
            try text.write(to: ledgerURL, atomically: true, encoding: .utf8)
        } catch {
            throw LicenseError.ledgerWriteFailed(error.localizedDescription)
        }
        return index
    }

    // MARK: 其他

    /// 从任意文本里抠出凭证（买家常把整条消息转过来）
    func extractCode(from text: String) -> String? {
        let pattern = "CLIP1\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else { return nil }
        return String(text[matchRange])
    }
}
