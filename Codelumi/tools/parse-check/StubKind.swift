import Foundation

// 仅限 parse-check 脚手架编译使用：PickupKind 在 App 侧定义于 PickupModels.swift
// （该文件依赖 SwiftUI，无法独立编译）。这里维护一份最小等价桩。
// ⚠️ 若 App 侧 PickupKind 增删 case，必须同步这里。

enum PickupKind: String, Equatable {
    case code
    case waybill
    case tail
    case special
}
