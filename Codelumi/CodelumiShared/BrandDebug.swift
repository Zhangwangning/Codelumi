import Foundation

// 临时诊断：记录品牌图标解析结果到 App Group（App 与小组件都能写）
enum BrandDebug {
    private static let file = "brand-debug.log"
    private static var url: URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PickupStorage.appGroupID) else { return nil }
        return base.appendingPathComponent(file)
    }
    static func trace(_ line: String) {
        guard let url else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(stamp)] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
