import Foundation

// MARK: ============================================================================
// 训练样本库（2026-11-05 主人：「帮助改进Codelumi」A+B 方案）
//
// App 内**不能训练模型**（Create ML 只在 Mac 上跑）。这里做的是：
//   收集用户手动提供的短信样本与标注 → 存本地 → 用户主动导出（分享 / 邮件）给开发者
//   → 开发者在 Mac 上重训 → 发新版本。
//
// 🔴 隐私口径（主人口径）：
//   · 样本**只由用户手动提供**，属于授权数据；App 不会自动收集、不会后台上传；
//   · 导出前对手机号、身份证、邮箱做**脱敏**；
//   · 随样本一起导出的只有 App 日志（版本、系统、错误码），不含其它隐私。
// ============================================================================

struct TrainingSample: Codable, Identifiable {
    var id: UUID = UUID()
    /// 已脱敏的短信原文
    var text: String
    /// pickup / other
    var label: String
    var code: String?
    var address: String?
    /// 短信平台（拼多多 / 菜鸟 …）。有些短信没有快递公司，只有平台。2026-11-08 新增
    var platform: String?
    /// 快递柜柜位（如「A-12」）。2026-11-08 新增；老样本没有这个字段 → 解码为 nil
    var locker: String?
    var note: String?
    var createdAt: Date = Date()
    var appVersion: String
    var osVersion: String
    var machine: String
}

enum TrainingSampleStore {
    private static var dirURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Training", isDirectory: true)
    }
    private static var fileURL: URL { dirURL.appendingPathComponent("samples.json") }

    static func load() -> [TrainingSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder.iso8601.decode([TrainingSample].self, from: data) else { return [] }
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func add(text: String, label: String, code: String?,
                    address: String?, platform: String? = nil,
                    locker: String? = nil, note: String?) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return false }
        var list = load()
        list.append(TrainingSample(
            text: mask(trimmed),
            label: label,
            code: cleanOptional(code),
            address: cleanOptional(address),
            platform: cleanOptional(platform),
            locker: cleanOptional(locker),
            note: cleanOptional(note),
            appVersion: AppVersion.display,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            machine: DeviceProfile.machineID
        ))
        return save(list)
    }

    /// 编辑已有样本（文本/判定/字段都能改；时间与设备信息保持原样）
    @discardableResult
    static func update(id: UUID, text: String, label: String,
                       code: String?, address: String?,
                       platform: String?, locker: String?, note: String?) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return false }
        var list = load()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return false }
        list[index].text = mask(trimmed)
        list[index].label = label
        list[index].code = cleanOptional(code)
        list[index].address = cleanOptional(address)
        list[index].platform = cleanOptional(platform)
        list[index].locker = cleanOptional(locker)
        list[index].note = cleanOptional(note)
        return save(list)
    }

    static func delete(id: UUID) {
        var list = load()
        list.removeAll { $0.id == id }
        _ = save(list)
    }

    static func clear() {
        _ = save([])
    }

    private static func cleanOptional(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }

    private static func save(_ list: [TrainingSample]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let data = try JSONEncoder.pretty.encode(list)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            DiagnosticsLog.record("training", "save failed reason=\(error.localizedDescription.count)字")
            return false
        }
    }

    /// 导出用的 JSONL（一行一条，方便直接灌进训练脚本）
    static func exportData() -> Data {
        let encoder = JSONEncoder.pretty
        let lines = load().map { sample -> String in
            (try? encoder.encode(sample)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    // MARK: 脱敏

    /// 手机号 → 138****1234；身份证 → 前4****后2；邮箱 → 首字母***@域
    static func mask(_ text: String) -> String {
        var s = text
        s = replace(#"\b1[3-9]\d{9}\b"#, in: s) { value in
            let a = value.prefix(3), b = value.suffix(4)
            return "\(a)****\(b)"
        }
        s = replace(#"\b\d{17}[\dXx]\b"#, in: s) { value in
            let a = value.prefix(4), b = value.suffix(2)
            return "\(a)**********\(b)"
        }
        s = replace(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: s) { value in
            guard let at = value.firstIndex(of: "@") else { return "***@***" }
            return String(value[value.startIndex]) + "***" + String(value[at...])
        }
        return s
    }

    private static func replace(_ pattern: String, in input: String,
                                _ transform: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return input }
        var result = input
        let matches = re.matches(in: input, range: NSRange(input.startIndex..., in: input))
        for m in matches.reversed() {
            guard let r = Range(m.range, in: result) else { continue }
            result.replaceSubrange(r, with: transform(String(result[r])))
        }
        return result
    }
}

private extension JSONDecoder {
    /// 🔴 必须与 `JSONEncoder.pretty` 的 `dateEncodingStrategy = .iso8601` **成对**，
    /// 否则解码一律失败 → 列表永远显示「已添加 0 条」（2026-11-07 踩坑）。
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }
}
