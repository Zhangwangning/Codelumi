import Foundation

// MARK: ============================================================================
// 构建期开关
//
// 内测分发的 **Release** 包要尽量少带内部东西：截图脚手架（`SCREEN=…`）能直接
// 打开各种内部页面、看到调试文案，反编译时也是最现成的"说明书"。
// Debug（自己真机调试 / 模拟器截图）继续保留，不受影响。
// ============================================================================

enum BuildFlags {
    /// 是否启用 `SCREEN` 等环境变量脚手架。**只有 Debug 为真。**
    static var scaffoldsEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
