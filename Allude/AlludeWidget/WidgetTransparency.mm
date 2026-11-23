//
//  WidgetTransparency.mm
//  AlludeWidget
//
//  「可用时使用真正透明」的**真身**。
//
//  ============================================================================
//  为什么需要这坨东西（2026-11-23 老大的第 N 次追问）
//  ============================================================================
//  iOS 的小组件不是你自己画在桌面上的，而是 WidgetKit 渲染成一张图、
//  由 SpringBoard（主屏进程）**贴**到壁纸上。贴的时候 SpringBoard 会按
//  widget descriptor 里的设置给这张图垫一层「安全背景」—— 浅色下就是那块
//  白卡。SwiftUI 侧再怎么 `.containerBackground(.clear)` 也改不到这一步：
//  背景是**宿主进程**的决定，不是视图 decides。
//
//  公开 API 到 `containerBackgroundRemovable(_:)` 就断了（WWDC 2025 那套
//  「Clear / Tinted 外观下移除背景」的说明也只覆盖系统自己挑外观的情形）。
//  想要「默认外观下也真透明」，全行业（Widgy / Top Widgets / 各种透明小组件）
//  走的是同一条私有路：**让 descriptor 自己声明「我要透明」**。
//
//  做法（源自 pookjw/ClearAndBlurredWidgets，Christian 在 X 上公开）：
//  · 在**小组件扩展进程**里 swizzle WidgetKit 的
//    `_TtCC9WidgetKit24WidgetExtensionXPCServer14ExportedObject`
//    `getAllCurrentDescriptorsWithCompletion:` —— 这是扩展把自己的 descriptor
//    交给宿主的唯一出口；
//  · 拦住返回值，把我们的 descriptor `mutableCopy` 一份，调私有 setter：
//        setBackgroundRemovable:YES
//        setTransparent:YES
//        setPreferredBackgroundStyle: 0x1（透明）/ 0x2（模糊）
//        setSupportsVibrantContent:YES（模糊时）
//  · 重新编码后交给宿主。SpringBoard 收到「这个 widget 要透明」，就不垫底了。
//
//  🔴 三条必须记住的事：
//  1. 全是**运行时字符串派发**（objc_lookUpClass / sel_registerName），
//     二进制里没有任何私有符号 —— 这是它能在 App Store 上架的原因，
//     但也意味着**方法名一改就静默失效**。所以每处都判空、失败就原样返回。
//  2. 只在 `allude.widget.clear` 打开时才动手；关着直接走原实现，
//     零开销、零风险。
//  3. 本文件必须按 **MRC** 编译（`-fno-objc-arc`，见 pbxproj 的
//     COMPILER_FLAGS）—— 它故意不持 ARC，跟着 pookjw 原实现走。
// ============================================================================

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const AlludeAppGroup = @"group.com.jikezhang.allude";

#pragma mark - 诊断

/// 把「扩展这边到底有没有接上」写给 App 侧看。
///
/// 跨进程调试没有控制台可看（TestFlight 包更看不到日志），只能借 App Group 当信箱：
/// 扩展在 `+load` 与每次改写 descriptor 时各写一次，App 的「设置 › 小组件」把结果
/// 显示成一行小字。真机上一眼就能分清是「没装到这一版」「系统接口变了」还是
/// 「接口接上了但系统仍然不给透明」—— 这三种情况的修法完全不同。
static NSString *const AlludeDiagSwizzled = @"allude.diag.widget.swizzled";
static NSString *const AlludeDiagPatched = @"allude.diag.widget.lastPatched";
static NSString *const AlludeDiagAt = @"allude.diag.widget.at";
static NSString *const AlludeDiagArgc = @"allude.diag.widget.argc";

static void AlludeDiagWrite(NSString *key, id value) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:AlludeAppGroup];
    if (defaults == nil) { return; }
    [defaults setObject:value forKey:key];
    [defaults release];
}

#pragma mark - 换掉 descriptor 的那一层

/// 与 WidgetKit 内部 `DescriptorFetchResult` 同构的一个壳：
/// 只声明三个数组字段，靠 `NSSecureCoding` 走一遍「解出来 → 改 → 再塞回去」。
@interface AlludeDescriptorFetchResult : NSObject <NSSecureCoding> {
    NSArray *_activityDescriptors;
    NSArray *_controlDescriptors;
    NSArray *_widgetDescriptors;
}
@end

@implementation AlludeDescriptorFetchResult

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        Class baseClass = objc_lookUpClass("CHSBaseDescriptor");
        Class controlClass = objc_lookUpClass("CHSControlDescriptor");
        Class widgetClass = objc_lookUpClass("CHSWidgetDescriptor");

        NSMutableSet *activityClasses = [NSMutableSet setWithObject:NSArray.class];
        if (baseClass) { [activityClasses addObject:baseClass]; }
        NSMutableSet *controlClasses = [NSMutableSet setWithObject:NSArray.class];
        if (controlClass) { [controlClasses addObject:controlClass]; }
        NSMutableSet *widgetClasses = [NSMutableSet setWithObject:NSArray.class];
        if (widgetClass) { [widgetClasses addObject:widgetClass]; }

        NSArray *activityDescriptors = [coder decodeObjectOfClasses:activityClasses forKey:@"activityDescriptors"];
        NSArray *controlDescriptors = [coder decodeObjectOfClasses:controlClasses forKey:@"controlDescriptors"];
        NSArray *widgetDescriptors = [coder decodeObjectOfClasses:widgetClasses forKey:@"widgetDescriptors"];

        // 🔴 2026-11-23 晚（343 读数「接口 ok · App 开 · 小组件读到 clear · 声明关」）：
        //    宿主取 descriptor 的时机**不由我们控制** —— 它在添加小组件那一刻取一次，
        //    之后一直用缓存。若那一刻开关是关的，就记为 "声明关"，之后再开开关也不会重取，
        //    于是永远不透。所以：**无条件**声明透明。
        //    外观由我们自己画的东西决定 —— 关掉开关时 `WidgetSurface` 会铺一层实色，
        //    用户看到的仍是原来那张卡；打开开关才什么都不画，壁纸自然透出来。
        // 玻璃由我们自己的 Material 层画（`WidgetSurface.glassLayer`），
        // descriptor 这边只负责一件事：别让宿主垫底。
        BOOL glass = NO;

        SEL backgroundRemovableSel = sel_registerName("setBackgroundRemovable:");
        SEL transparentSel = sel_registerName("setTransparent:");
        SEL backgroundStyleSel = sel_registerName("setPreferredBackgroundStyle:");
        SEL vibrantSel = sel_registerName("setSupportsVibrantContent:");
        // 🔴 2026-11-23 第 5 次：ChronoServices 里还有个
        //    `backgroundViewPolicy`（unsigned long，且有 setter）。
        //    宿主在挑渲染样式时用它决定"底板画不画" —— 这正是 Medium 那篇
        //    逆向分析里提到的 `backgroundViewPolicy`。之前几版都没碰过它。
        SEL backgroundViewPolicySel = sel_registerName("setBackgroundViewPolicy:");

        NSMutableArray *patched = [[NSMutableArray alloc] initWithCapacity:widgetDescriptors.count];

        for (id descriptor in widgetDescriptors) {
            // 系统换了私有接口（没有那几个 setter）→ 原样放过，绝不动别人的 descriptor。
            if ([descriptor respondsToSelector:transparentSel] == NO
                || [descriptor respondsToSelector:backgroundStyleSel] == NO) {
                [patched addObject:descriptor];
                continue;
            }

            id mutableDescriptor = [descriptor mutableCopy];
            if (mutableDescriptor == nil) {
                [patched addObject:descriptor];
                continue;
            }

            if ([mutableDescriptor respondsToSelector:backgroundRemovableSel]) {
                reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(mutableDescriptor,
                                                                      backgroundRemovableSel,
                                                                      YES);
            }
            reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(mutableDescriptor,
                                                                  transparentSel,
                                                                  YES);
            // 🔴 2026-11-23 第 4 次：`setTransparent:` 在 iOS 26 已废弃（ChronoServices 原话
            //    「please migrate away」），真正生效的是这个 `preferredBackgroundStyle`。
            //    0x1 试过 → 宿主仍垫底（角标 b1）。这一版换 **0x2**，
            //    并把写进去的值记到 App Group，角标里会带出来，便于对照。
            NSUInteger style = 0x2;
            reinterpret_cast<void (*)(id, SEL, NSUInteger)>(objc_msgSend)(mutableDescriptor,
                                                                         backgroundStyleSel,
                                                                         style);
            // 🔴 2026-11-23 晚：ChronoServices 里有句警告 ——
            //    「Widget descriptor `isTransparent` called, please migrate away」，
            //    说明 iOS 26 起 `transparent` 已经是废弃属性，真正生效的是
            //    `preferredBackgroundStyle`。所以把 vibrant 一并打开，
            //    让宿主至少有"内容自绘、背景别垫"的依据。
            AlludeDiagWrite(@"allude.diag.widget.style", @(style));

            // 背景视图策略：0 自动 / 1 交给 App / 2 由系统画。先试 1（"别管，交给我"）。
            NSUInteger policy = 1;
            if ([mutableDescriptor respondsToSelector:backgroundViewPolicySel]) {
                reinterpret_cast<void (*)(id, SEL, NSUInteger)>(objc_msgSend)(mutableDescriptor,
                                                                             backgroundViewPolicySel,
                                                                             policy);
                AlludeDiagWrite(@"allude.diag.widget.policy", @(policy));
            } else {
                AlludeDiagWrite(@"allude.diag.widget.policy", @(-1));
            }

            if ([mutableDescriptor respondsToSelector:vibrantSel]) {
                reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(mutableDescriptor,
                                                                       vibrantSel,
                                                                       YES);
            }

            [patched addObject:mutableDescriptor];
            [mutableDescriptor release];
        }

        _widgetDescriptors = [patched copy];
        [patched release];
        _controlDescriptors = [controlDescriptors retain];
        _activityDescriptors = [activityDescriptors retain];

        // 给 App 侧留个读数：这次改写了几款、当时的开关是什么值。
        AlludeDiagWrite(AlludeDiagPatched, @((NSInteger)_widgetDescriptors.count));
        AlludeDiagWrite(AlludeDiagAt, [NSDate date]);
    }
    return self;
}

- (void)dealloc {
    [_activityDescriptors release];
    [_controlDescriptors release];
    [_widgetDescriptors release];
    [super dealloc];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_activityDescriptors forKey:@"activityDescriptors"];
    [coder encodeObject:_controlDescriptors forKey:@"controlDescriptors"];
    [coder encodeObject:_widgetDescriptors forKey:@"widgetDescriptors"];
}

@end

#pragma mark - swizzle

namespace allude_widget_xpc_server {

    namespace getAllCurrentDescriptors {

        void (*originalImplementation)(id, SEL, id) = NULL;

        /// 解一遍、改一遍、再编回去 —— 因为宿主拿到的就是这个 fetch result 的归档。
        void replacement(id self, SEL _cmd, void (^completion)(id fetchResult)) {
            if (originalImplementation == NULL) { return; }

            originalImplementation(self, _cmd, ^(id fetchResult) {
                if (fetchResult == nil) { return; }

                NSError *error = nil;

                NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
                [fetchResult encodeWithCoder:archiver];
                NSData *encoded = archiver.encodedData;
                [archiver release];

                NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:encoded
                                                                                            error:&error];
                if (error != nil || unarchiver == nil) {
                    [unarchiver release];
                    completion(fetchResult);
                    return;
                }

                AlludeDescriptorFetchResult *patchedResult =
                    [[AlludeDescriptorFetchResult alloc] initWithCoder:unarchiver];
                [unarchiver release];

                NSKeyedArchiver *reArchiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
                [patchedResult encodeWithCoder:reArchiver];
                NSData *reEncoded = reArchiver.encodedData;
                [reArchiver release];
                [patchedResult release];

                NSKeyedUnarchiver *reUnarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:reEncoded
                                                                                              error:&error];
                if (error != nil || reUnarchiver == nil) {
                    [reUnarchiver release];
                    completion(fetchResult);
                    return;
                }

                Class resultClass = objc_lookUpClass("_TtC9WidgetKit21DescriptorFetchResult");
                if (resultClass == Nil) {
                    [reUnarchiver release];
                    completion(fetchResult);
                    return;
                }

                id rebuilt = reinterpret_cast<id (*)(id, SEL, id)>(objc_msgSend)([resultClass alloc],
                                                                                @selector(initWithCoder:),
                                                                                reUnarchiver);
                [reUnarchiver release];

                if (rebuilt == nil) {
                    completion(fetchResult);
                    return;
                }
                completion(rebuilt);
                [rebuilt release];
            });
        }

        /// 找不到方法（系统改了名字）就什么都不做 —— 宁可没透明，也不能崩。
        void install(void) {
            // 先留一条"扩展进程起来过"的时间戳 —— 宿主可能压根不来取 descriptor
            // （它缓存了），那时 `swizzled` 有值但 `at` 永远没有，两者一比就知道
            // 是"没挂上"还是"挂上了但没人调"。
            AlludeDiagWrite(AlludeDiagAt, [NSDate date]);

            Class serverClass = objc_lookUpClass("_TtCC9WidgetKit24WidgetExtensionXPCServer14ExportedObject");
            if (serverClass == Nil) {
                AlludeDiagWrite(AlludeDiagSwizzled, @"noClass");
                return;
            }

            SEL selector = sel_registerName("getAllCurrentDescriptorsWithCompletion:");
            Method method = class_getInstanceMethod(serverClass, selector);
            if (method == NULL) {
                AlludeDiagWrite(AlludeDiagSwizzled, @"noMethod");
                return;
            }

            // 多一道保险：签名必须是 (self, _cmd, completion)。
            // 🔴 2026-11-23 修：`method_getNumberOfArguments` 把 self 与 _cmd 也算进去，
            //    所以正确值是 **3** —— 我上一版写成 4，于是每台机器都走到 "签名不对"、
            //    一次都没挂上（342 的诊断读数原话就是「接口 签名不对」）。
            //    现在把实际个数一并记下来，将来系统真变了也能一眼看出。
            NSUInteger argc = method_getNumberOfArguments(method);
            AlludeDiagWrite(AlludeDiagArgc, @(argc));
            if (argc != 3) {
                AlludeDiagWrite(AlludeDiagSwizzled, @"badArgs");
                return;
            }

            originalImplementation = reinterpret_cast<decltype(originalImplementation)>(method_getImplementation(method));
            method_setImplementation(method, reinterpret_cast<IMP>(replacement));
            AlludeDiagWrite(AlludeDiagSwizzled, @"ok");
        }
    }
}

#pragma mark - 第二道钩子：描述符编码

// 🔴 2026-11-23 晚：349 的角标（s-8·p-8）证明**第一道钩子根本没被调用** ——
//    SpringBoard 用的不是我们截的那个 XPC 方法（或者只在安装时调过一次）。
//    所以再加一道更底层的：任何 descriptor 要跨进程传给宿主，都必须走
//    `-encodeWithCoder:`。这里拦一次，不依赖具体是哪个 XPC 入口。
//
//    注意：只有可变子类（CHSMutableWidgetDescriptor）才带 setter，
//    不可变的直接放过 —— 不能在别人的对象上瞎改。

static IMP gOriginalDescriptorEncode = NULL;

static void AlludeDescriptorEncode(id self, SEL _cmd, NSCoder *coder) {
    if (gOriginalDescriptorEncode == NULL) { return; }

    SEL removableSel = sel_registerName("setBackgroundRemovable:");
    SEL transparentSel = sel_registerName("setTransparent:");
    SEL styleSel = sel_registerName("setPreferredBackgroundStyle:");
    SEL vibrantSel = sel_registerName("setSupportsVibrantContent:");
    SEL policySel = sel_registerName("setBackgroundViewPolicy:");

    if ([self respondsToSelector:transparentSel] && [self respondsToSelector:styleSel]) {
        if ([self respondsToSelector:removableSel]) {
            reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(self, removableSel, YES);
        }
        reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(self, transparentSel, YES);
        reinterpret_cast<void (*)(id, SEL, NSUInteger)>(objc_msgSend)(self, styleSel, 0x2);
        if ([self respondsToSelector:vibrantSel]) {
            reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(self, vibrantSel, YES);
        }
        if ([self respondsToSelector:policySel]) {
            reinterpret_cast<void (*)(id, SEL, NSUInteger)>(objc_msgSend)(self, policySel, 1);
        }
        AlludeDiagWrite(@"allude.diag.widget.style", @(2));
        if ([self respondsToSelector:policySel]) {
            AlludeDiagWrite(@"allude.diag.widget.policy", @(1));
        }
        AlludeDiagWrite(AlludeDiagPatched, @(1));
        AlludeDiagWrite(AlludeDiagAt, [NSDate date]);
    }

    reinterpret_cast<void (*)(id, SEL, id)>(gOriginalDescriptorEncode)(self, _cmd, coder);
}

static void AlludeInstallEncodeHook(void) {
    Class descClass = objc_lookUpClass("CHSWidgetDescriptor");
    if (descClass == Nil) {
        AlludeDiagWrite(@"allude.diag.widget.encode", @(NO));
        return;
    }
    SEL sel = @selector(encodeWithCoder:);
    Method method = class_getInstanceMethod(descClass, sel);
    if (method == NULL) {
        AlludeDiagWrite(@"allude.diag.widget.encode", @(NO));
        return;
    }
    const char *types = method_getTypeEncoding(method);
    gOriginalDescriptorEncode = method_getImplementation(method);

    // 优先给这个类单独加一个实现（影响面最小）；加不上再替换原实现。
    if (class_addMethod(descClass, sel, (IMP)AlludeDescriptorEncode, types)) {
        AlludeDiagWrite(@"allude.diag.widget.encode", @(YES));
        return;
    }
    method_setImplementation(method, (IMP)AlludeDescriptorEncode);
    AlludeDiagWrite(@"allude.diag.widget.encode", @(YES));
}

#pragma mark - 入口

/// 一个只为了 `+load` 而存在的类：扩展进程一起来就挂上，不用 App 侧调任何东西。
@interface AlludeWidgetTransparencyLoader : NSObject
@end

@implementation AlludeWidgetTransparencyLoader

+ (void)load {
    allude_widget_xpc_server::getAllCurrentDescriptors::install();
    AlludeInstallEncodeHook();
}

@end
