import Foundation
import StoreKit

// MARK: ============================================================================
// 内购（StoreKit 2）· 免费下载 + 订阅解锁
//
// 2026-10-31 主人定（参考 Infuse）：App 免费下载，三档可选
//   · 每年  自动续期订阅
//   · 终身  非消耗型，一次买断（主推）
//   ⚠️ 价格一律取 Product.displayPrice，代码与文档里不要写死金额（月度已下架）
//
// 三档解锁的是同一件事，所以权益判定 = **任意一档有效即算完整版**。
//
// 🔴 订阅会过期，权益**必须带到期时间**写进快照：
//    小组件进程不联网、也不该去问 StoreKit，它只读 `entitlement.json`。
//    没有 `expiresAt` 的话，订阅过期后小组件会一直按完整版渲染，
//    直到用户恰好打开一次主 App —— 那是"过期了还在用"的口子。
//
// ⚠️ 调试：本地用 `Allude.storekit` 配置（Scheme → Run 已挂上），
//    只能在 Xcode 里跑通，`simctl launch` 不会注入该配置。
// ============================================================================

@MainActor
final class PurchaseStore: ObservableObject {

    // MARK: 商品

    /// 三档商品。`rawValue` 拼进 product ID —— 改名字等于换商品，已购用户会丢权益。
    enum Plan: String, CaseIterable, Identifiable {
        // 顺序即界面顺序：**买断排第一**（主推），订阅在后
        case lifetime, yearly, monthly

        var id: String { rawValue }

        /// 必须与 App Store Connect 里建的 ID 完全一致。
        ///
        /// 🔴 年订阅不叫 `...pro.yearly`：2026-11-11 在 ASC 里误把年费建成了
        ///    「非消耗型项目」，删除后该 product ID **被苹果永久占用、不能复用**
        ///    （官方文档：product ID 一旦分配给某个内购项目，即使删除原项目也不能
        ///    在同一 App 内再次使用）。所以年订阅改用 `...pro.annual`。
        ///    `rawValue` 保持 `yearly` 不变（权益快照/旧数据靠它解码）。
        var productID: String {
            switch self {
            case .lifetime: "com.jikezhang.allude.pro.lifetime"
            case .yearly:   "com.jikezhang.allude.pro.annual"
            case .monthly:  "com.jikezhang.allude.pro.monthly"
            }
        }

        var title: String {
            switch self {
            case .monthly: "每月"
            case .yearly: "每年"
            case .lifetime: "终身"
            }
        }

        /// 周期说明（买断没有周期）
        var period: String {
            switch self {
            case .monthly: "按月自动续期"
            case .yearly: "按年自动续期"
            case .lifetime: "一次付费，永久使用，不续期"
            }
        }

        /// 横排卡片第三行的极短说明（一行放得下）
        var shortPeriod: String {
            switch self {
            case .monthly: "按月"
            case .yearly: "按年"
            case .lifetime: "永久"
            }
        }

        /// 界面上的推荐位。2026-10-31 主人定：**主推买断** ——
        /// 一次付清、永久使用，用户不用记着取消订阅，售后也少。
        var isRecommended: Bool { self == .lifetime }
    }

    static let shared = PurchaseStore()

    /// 🔴 2026-11-08 主人：**只卖两档** —— 终身（主推）与每年。
    /// `monthly` 这个 case 留着只为兼容旧数据解码（App Store 里也已下架），
    /// 界面与商品请求都不再出现它。
    static var displayedPlans: [Plan] { [.lifetime, .yearly] }

    /// 限时促销用的「永久会员」——ASC 里单独建的非消耗型（`…pro.lifetime.99`）。
    ///
    /// 🔴 2026-11-23 老大要在某段时间里用 9.9 卖永久：内购**没有折扣工具**，
    ///    唯一干净的做法是单独建一个商品、活动期在售、结束下架。
    ///    所以它**不进界面列表**（不出现第二张卡），只做两件事：
    ///    ① 在售时替 `lifetime` 接单（价格自然就是促销价）；
    ///    ② 买了它同样算 Pro 永久（下面 `allProductIDs` 一并纳入权益判定）。
    static let promoLifetimeProductID = "com.jikezhang.allude.pro.lifetime.99"

    /// 请求商品与判定权益时用的全集 —— 比界面展示的多一个促销款。
    static var allProductIDs: [String] { displayedPlans.map(\.productID) + [promoLifetimeProductID] }

    // MARK: 状态

    /// 已取到的商品（按 product ID 索引）。取不到时为空，界面据此禁用购买键。
    @Published private(set) var products: [String: Product] = [:]
    /// 当前是否已解锁（来自 `Transaction.currentEntitlements`，已验签）
    @Published private(set) var isOwned = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingPlan: Plan?
    /// 给界面看的一句话提示（取商品失败 / 购买成功等）
    @Published private(set) var message: String?

    private var updatesTask: Task<Void, Never>?
    /// 监听商店地区变化（2026-11-16）。
    ///
    /// 🔴 `Product.displayPrice` 是 StoreKit **按当前 Storefront 格式化好的字符串**，
    ///    App 这边一个字符都没拼。TestFlight 刚装好时系统还没把沙盒账号的
    ///    中国区 storefront 同步过来，StoreKit 会先回落到内购创建时的美元基准价
    ///    （`$0.99`）；等地区就绪才变人民币。以前商品一旦取到就不再重拉，
    ///    用户只能干等系统自己切，所以这里监听 `Storefront.updates` 主动刷新。
    private var storefrontTask: Task<Void, Never>?
    private var started = false

    private init() {}

    /// 某档的商店价格；取不到就是 nil，界面显示「—」并禁用按钮。
    /// **不要写死价格**：定价在 App Store Connect 改，代码里写死就对不上。
    func price(for plan: Plan) -> String? {
        products[resolvedProductID(for: plan)]?.displayPrice
    }

    /// 这一档实际生效的商品 ID。
    ///
    /// 买断档优先用限时款：它下架后 StoreKit 就取不到，这里自动回落到常驻款 ——
    /// 活动结束不需要改代码、也不需要发版。
    func resolvedProductID(for plan: Plan) -> String {
        if plan == .lifetime, products[Self.promoLifetimeProductID] != nil {
            return Self.promoLifetimeProductID
        }
        return plan.productID
    }

    var canPurchase: Bool { !products.isEmpty }

    // MARK: 启动

    func start() {
        guard !started else { return }
        started = true

        // 交易更新要一直听着：续期、Ask to Buy 批准、跨设备购买、退款都从这里来
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlement()
            }
        }

        // 商店地区一变就重拉商品：这是「先显示 $0.99、过一会儿变 ¥」能立刻
        // 收敛的关键。只在 `start()` 里挂一次，页面开关不会重复注册。
        storefrontTask = Task { [weak self] in
            for await _ in Storefront.updates {
                guard let self else { return }
                await self.loadProducts()
            }
        }

        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await Product.products(for: Self.allProductIDs)
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            #if DEBUG
            // 排查「价格显示成美元」时，一条日志就能分清是 storefront 没就绪、
            // 商品没生效，还是代码格式化错了（答案是前两者，App 只显示原串）。
            // ⚠️ `Storefront.current` 是 async 属性，必须单独 await 后再取值。
            let front = await Storefront.current
            print("[allude-iap] storefront=\(front?.countryCode ?? "nil") "
                  + (list.isEmpty
                     ? "products=(empty)"
                     : list.map { "\($0.id)=\($0.displayPrice)" }.joined(separator: " ")))
            #endif
            if products.isEmpty {
                message = "暂时取不到商品信息，请稍后再试"
            } else {
                message = nil
            }
        } catch {
            message = "取商品失败：\(error.localizedDescription)"
        }
    }

    // MARK: 购买 / 恢复

    func purchase(_ plan: Plan) async {
        guard let product = products[resolvedProductID(for: plan)] else {
            message = "商品还没加载好，请稍后重试"
            return
        }
        purchasingPlan = plan
        message = nil
        defer { purchasingPlan = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlement()
                    message = "已解锁 Codelumi Pro"
                case .unverified:
                    message = "购买凭据校验失败，请稍后重试"
                }
            case .userCancelled:
                break                       // 用户自己取消，不弹错误
            case .pending:
                message = "购买待确认，完成后会自动生效"
            @unknown default:
                break
            }
        } catch {
            message = "购买失败：\(error.localizedDescription)"
        }
    }

    func restore() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()       // 会要求输入 Apple ID 密码
            // 同步之后仍为空 = 这个 Apple ID 确实没有有效权益，此时降级是可信的
            await refreshEntitlement(allowDowngrade: true)
            if !isOwned { message = "这个 Apple ID 下没有找到有效订阅或购买记录" }
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    // MARK: 权益

    /// 扫一遍已购列表，算出「是否解锁」与「最晚到期时间」。
    ///
    /// `currentEntitlements` 对订阅只返回**仍然有效**的那些，所以到期自然消失；
    /// 非消耗型则一直返回。两者混在一起取 max：有终身就是 nil（永不过期）。
    ///
    /// 🔴 `allowDowngrade` 默认 **false**：这个集合读的是本机收据，
    ///    刚重装 / 离线 / 商店暂时不可用时会返回空 —— 但用户明明买过。
    ///    无条件照空集合降级 = 换机断网就掉权益，而且没有报错。
    ///    只有用户主动「恢复购买」（`AppStore.sync()` 之后）才承认"确实没有"。
    func refreshEntitlement(allowDowngrade: Bool = false) async {
        var owned = false
        var latestExpiry: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.allProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard let expiry = transaction.expirationDate else {
                // 非消耗型：没有到期时间 = 永久
                owned = true
                latestExpiry = nil
                break
            }
            guard expiry > Date() else { continue }
            owned = true
            latestExpiry = max(latestExpiry ?? .distantPast, expiry)
        }

        if owned {
            isOwned = true
            EntitlementSnapshot.markStoreOwned(true, expiresAt: latestExpiry)
        } else if allowDowngrade {
            isOwned = false
            EntitlementSnapshot.markStoreOwned(false, expiresAt: nil)
        } else {
            // 商店没给出结论：沿用快照（快照自己会按 expiresAt 判过期）
            isOwned = EntitlementSnapshot.licensedPro
        }
        PickupStore.shared.refreshEntitlement()
    }
}
