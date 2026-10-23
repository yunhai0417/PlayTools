# PlayTools 优化路线图

> 本文档是 fork 后的工程演进计划。按照阶段顺序逐项执行，每项完成后在对应条目标记 ✅。
> 原则：**保留技术内核（dyld interpose + ObjC swizzle + 触摸合成 + iOS/macOS 双 target 分离），只重构工程形态。渐进迁移，不重写，每一步独立可发布。**

## 已核实的现状（2026-10 基线）

| 问题 | 证据位置 |
|---|---|
| swizzle 调用集中在一个 `+load`，5 层嵌套 if-else，零失败处理（`objc_getClass` 返回 nil 时静默无操作） | `PlayTools/Controls/PTFakeTouch/NSObject+Swizzle.m:256-372`（374 行） |
| 版本硬门控 `@available(iOS 16.3/17.1)` 与类迁移（`FBSSceneSettings` → `FBSSceneSettingsCore`）交织 | 同上 259-332 行 |
| hook 方法以 NSObject category 形式污染所有类 | 同上 90-227 行 |
| 几何变换是纯逻辑但依赖全局变量，无法单测 | `PlayTools/PlayScreen.swift:9-64`（`mainScreenWidth` 等全局 `let`） |
| 设置 schema 三份拷贝：PlayCover 一份、本仓库 `AppSettingsData`、`AKPlugin.swift` 私有 `AKAppSettingsData`（5 字段手抄） | `PlaySettings.swift:104-137`、`AKPlugin.swift:13-19` |
| 日志散落且无体系：`NSLog`、`print`、文件写日志、"PC-DEBUG:" 前缀各自为政 | `PlayLoader.m`、`Toucher.swift:14-16`、`PlayedApple.swift:19-23` |
| 零测试；CI 仅有 SwiftLint `--strict` | `.github/workflows/SwiftLint.yml` |
| 宿主↔运行时仅靠 plist 文件单向通信，全部设置 `lazy` 缓存，改设置必须重启游戏 | `PlaySettings.swift:26-101` |

## 约束（执行时必须遵守）

- **pbxproj 是 objectVersion 55 手工工程**：新增源文件必须同时注册 `PBXFileReference`、`PBXBuildFile`、Group children、Sources build phase（四个位置），否则不参与编译。
- SwiftLint `--strict` 必须通过（`swiftlint --strict`）。
- 阶段 1 的迁移必须**行为等价**：同一设置矩阵下安装的 hook 集合前后不变。
- 新增 ObjC 可见 API 需 `@objc`（PlayLoader.m 通过 `PlayTools-Swift.h` 调用）。
- 每阶段完成后在真机（PlayCover 注入）验证一次冒烟：游戏可启动、键位生效。

---

## 阶段 0 — 诊断基建（P0，安全网，最先做）

### 0.1 统一日志模块 PCLog
- **目标**：os_log 封装，subsystem `io.playcover.PlayTools`，category 按模块划分（`loader` / `screen` / `input` / `keychain` / `bypass` / `plugin`）。
- **任务**：
  1. 新建 `PlayTools/Utils/PCLog.swift`（`@objc` 静态类，兼容 ObjC 调用；`privacy: .public`；提供 `PCLog.loader.info(...)` 风格 API 与统一 `[PC]` 前缀文案）
  2. 注册进 pbxproj（仅 PlayTools target）
  3. 迁移现有散落日志：`PlayLoader.m` 的 NSLog、`UserPluginLoader`/`PlaySettings` 的 print、`PlayKeychain.debugLogger`、`PTSwizzleLoader` 内 NSLog
- **验收**：Console.app 按 subsystem/category 过滤可见；`log stream --predicate 'subsystem == "io.playcover.PlayTools"'` 实时输出；grep 仓库无残留裸 `NSLog(`（除 Toucher 调试日志文件功能）。
- **状态**：✅ 完成（2026-10-20）。SwiftLint 0 违规；`xcodebuild -scheme PlayTools -destination 'generic/platform=iOS' build` 通过，产物含 PCLog 符号。注意：本机 Xcode 26.2 下 **必须用 scheme 构建，不能用 `-target`**（SPM 包模块图顺序 bug）。
- **遗留**：本机构建需经 ghfast.top 反代克隆 SPM 依赖（github 直连不通），已通过 commit 哈希校验（`4403152a...`）。

### 0.2 安全模式 safeMode
- **目标**：一个 plist 开关，让"游戏起不来"时能快速二分定位。safeMode=true 时只保留平台/设备伪造（uname/sysctl/dyld platform + ProMotion 等必需 hook），跳过全部可选 hook、PlayChain、UserPlugins。
- **任务**：
  1. `AppSettingsData` 增加 `var safeMode = false`（缺省关闭，兼容旧 plist）
  2. `PTSwizzleLoader +load`：除 `initWithRootMenu:` 外全部 hook 包裹 safeMode 判断
  3. `PlayLoader.m`：SecItem/UE 路径/usleep interpose 保留（属于伪造类）或按分析归为可选——**决定：SecItem PlayChain、UE 路径修复、usleep 节流均归可选**，safeMode 下直接透传系统实现
  4. `UserPluginLoader`：safeMode 下跳过 dlopen
  5. 启动时输出一行 `[PC] safeMode=ON, N hooks skipped`（走 PCLog）
- **验收**：手工在 plist 加 `safeMode: true`，游戏正常启动且无键位/菜单功能；日志可见 skipped 数。
- **状态**：✅ 代码完成（2026-10-20），lint + 构建通过。覆盖：PTSwizzleLoader 可选 swizzle（保留菜单注入与平台伪造）、PlayShadow 全部 bypass hook、PlayChain 六个 SecItem/SecKey interpose、UE 路径修复、usleep 节流、UserPluginLoader、键位初始化、屏幕旋转。启动时输出汇总日志。**待真机冒烟**；PlayCover 宿主侧需后续加 UI 开关（运行时读 plist 字段，缺省 false 向后兼容）

### 0.3 Hook 状态快照与崩溃转储
- **目标**：任何时刻能回答"装了哪些 hook、哪些失败、哪些被跳过"。
- **任务**：
  1. `HookStatusRegistry`：记录每个 hook 的 spec（类/selector/策略）与结果（applied/failed/classNotFound/skippedBySafeMode/skippedByCondition）
  2. `PTSwizzleLoader` 与 PlayLoader interpose 注册时全部上报
  3. 崩溃捕获：`NSSetUncaughtExceptionHandler` + SIGSEGV/SIGABRT/SIGBUS 信号处理器，把 registry 快照写到 `~/Library/Containers/io.playcover.PlayCover/Logs/<bundleId>-hooks.txt`
  4. 提供 in-game 菜单入口 dump 当前状态（挂到 MenuController 调试菜单）
- **验收**：人为制造一个 hook 失败（如假类名）能看到记录；kill -SEGV 游戏进程后能在 Logs 目录找到快照。
- **状态**：✅ 代码完成（2026-10-20），lint + 构建通过。`HookStatusRegistry` 经三个 swizzle helper 汇聚点自动记录（applied/failed + 原因）；interpose 16 项静态清单在构造器登记；`HookDiagnostics.installCrashHandlers()`（NSException + 5 信号，open/write 仅用预渲染字节）在 PlayLoader 构造器安装；Debug 菜单新增 "Export hook status snapshot"（⌘E）。**注意**：`objc_getClass` 返回 nil 时消息发给 nil、helper 不执行，classNotFound 粒度的记录留给 P1 声明式注册表（spec 显式声明类名后天然可判）。**待真机冒烟**。

---

## 阶段 1 — Hook 注册表化（合并原 #1/#2/#10）

### 1.1 声明式注册表
- **任务**：
  1. 定义 `HookSpec`：目标类名（可多个降级候选，如 `["FBSSceneSettingsCore", "FBSSceneSettings"]`）、selector、replacement、策略（`required` 启动失败必须可见 / `optional` 允许跳过）、生效条件闭包（读 PlaySettings）
  2. 装配器：`class_getInstanceMethod`/`class_getClassMethod` 探测 selector 实际在哪个候选类，逐个尝试直到命中；版本号判断只做兜底不再做首选
  3. 结果全部写入 HookStatusRegistry（复用 0.3）
- **验收**：注册表驱动安装；类不存在/selector 移动时自动降级并记录，单点失败不影响其他 hook。
- **状态**：✅ 完成 — `HookRegistry.swift`（模型 + 探测式装配器 `installOnCandidates`，候选类按新到旧排序，逐个 `NSClassFromString` + `class_get*Method` 探测，首个命中者安装；结果逐条写入 HookStatusRegistry，safeMode 跳过 optional 并记录）。

### 1.2 迁移 PTSwizzleLoader
- **任务**：把 374 行 `+load` 中的 ~25 个 swizzle 调用改为声明式注册（行为等价矩阵：resizableWindow/adaptiveDisplay/inverseScreenValues/windowFixMethod × iOS 版本）；`hook_*` 方法从 NSObject category 迁到独立容器类（消除 NSObject 污染）。
- **验收**：迁移前后在相同设置矩阵下 hook 集合一致（写一个 dump 对比脚本）；"适配新 macOS" 从改核心代码变为加一条注册项。
- **状态**：✅ 完成（主体）/ 🟡 遗留 —
  - 完成：`+load` 矩阵（~120 行 imperative 代码）整体替换为 `[HookRegistry installFromLoad]`；specs 定义在 `HookRegistrySpecs.swift`（A resizable / B·C adaptive±inverse / C-pre16.3 legacy 三件套 / D default / E always / F conditional，与原矩阵逐分支等价，含 `resolution==6` 时 else-if 语义与 window size 持久化副作用、Unity keyboard 延迟 0.01s）。新增自包含 C 桥接 `PTSwizzleOnClassNamed`（NSObject+Swizzle.h/.m）：不经过 `swizzleInstanceMethod:` 类目方法——该方法在 PlayShadow/BatteryLevel/MediaVolume/Swizzle 四处重复定义，运行时命中哪个是不确定的；桥接直接操作 runtime 并回报结果。
  - 遗留：① `hook_*` 方法仍留在 NSObject category（迁独立容器类需为每个目标类生成 @interface，风险大于收益，暂缓）；② 四处重复的 `swizzleInstanceMethod:` 类目未清理（PlayShadow/BatteryLevel/MediaVolume 各自内部调用仍走它们，属既有行为）。
  - 构建与 lint：`xcodebuild -scheme PlayTools` ✅，`swiftlint --strict` ✅；⏳ 待真机冒烟（注入后游戏可启动、窗口模式正确、Hook 快照导出核对 applied 集合）。

---

## 阶段 2 — Seam 层与单元测试（原 #3）

### 2.1 测试 target
- **任务**：pbxproj 新增 `PlayToolsTests`（iOS 单元测试 bundle，host 不可用则纯逻辑测试）；CI workflow 加 test job。
- **验收**：`xcodebuild test -scheme PlayTools` 绿。
- **状态**：✅ 完成（target 部分）— 无 host 的逻辑测试 bundle（`com.apple.product-type.bundle.unit-test`，不设 TEST_HOST）。**关键设计**：被测纯逻辑源文件直接双编译进测试 target，**不链接 PlayTools.framework**——framework 的 `+load`/constructor 会执行 DYLD_INTERPOSE 与 SecItem 挂钩，绝不能进测试 runner 进程。命令：`xcodebuild test -project PlayTools.xcodeproj -scheme PlayTools -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`（共享 scheme 已挂 TestAction）。CI test job 未做（仓库无 CI workflow，待宿主 fork 统一）。

### 2.2 几何变换纯函数化 + 用例
- **任务**：`PlayScreen.swift` 的 `toAspectRatio*` 家族改为 `ScreenGeometry` 结构（宽高/旋转/scaler 参数注入，消除全局 `let` 依赖）；覆盖 16:9/4:3/自定义/inverse/旋转矩阵用例。
- **验收**：变换逻辑全量单测覆盖。
- **状态**：✅ 完成 — 新增 `PlayTools/Utils/ScreenGeometry.swift`（仅 CoreGraphics，width/height/scaler 全注入；aspectRatio/size/sizeReversed/rect(multiplier:)/rectReversed），双编译进 PlayToolsTests。`PlayScreen.swift` 的 4 个全局 `let`（mainScreenWidth/mainScreenHeight/customScaler/isInvertFixEnabled）与 CGSize/CGRect 扩展全部改为委托懒加载全局 `screenGeometry`（首访问时机与原 lazy 语义一致，含 inverse 预交换）；对外 API 签名不变，调用点零改动。11 个用例：16:9 横/竖、4:3、自定义 64:27、正方形、size 对、scaler 乘算、reversed 保原点、inverse 工厂交换语义。旋转矩阵实际参与的是键位路径（displayRotation 在 Keymapping/Editor 侧），在 2.3 补。

### 2.3 键位坐标换算用例
- **任务**：keymap 相对坐标（0-1）↔ 屏幕绝对坐标换算抽纯函数 + 用例（含 inverse、分辨率变化）。

### 2.4 PlayChain 序列化用例
- **任务**：`PlayKeychain` add/copyMatching/update/delete 的 plist 语义 + `PlayKeychainDB` SQLite 持久化用例（临时目录）。

### 2.5 TouchSink seam
- **任务**：`ActionDispatcher` → `Toucher` 之间抽协议，逻辑层可注入 fake sink 单测分发正确性。

---

## 阶段 3 — 设置契约统一（原 #4）

### 3.1 仓库内去重（先做）
- **任务**：删除 `AKPlugin.swift` 的 `AKAppSettingsData`；`AppSettingsData` 移入单文件 `PlayToolsContracts.swift`，同时加入 PlayTools 与 AKInterface 两个 target 的 Sources（单一源文件双编译，无包依赖）。
- **验收**：仓库内 schema 只剩一份；AKInterface 行为不变（hideTitleBar/floatingWindow/aspectRatio 读取路径改走共享类型）。

### 3.2 抽 SwiftPM 契约包
- **任务**：`PlayToolsContract` package（纯 Foundation Codable），本仓库与 fork 的 PlayCover 共同依赖；`version` 字段配套 decode 兼容规则。
- **验收**：三份拷贝归一；宿主 fork 切换后装老游戏不崩、新字段缺省合理。

---

## 阶段 4 — UDS 活通道（原 #5，产品力开始）

- **任务**：
  1. 协议：Unix domain socket + JSON lines，版本握手；指令集 `keymap.update` / `settings.refresh` / `diag.dump` / `log.level`
  2. 运行时侧客户端（PlayTools 内，失败静默降级为现行为）
  3. 宿主侧服务端（fork 的 PlayCover）
  4. 第一个落地功能：键位热更新（不重启游戏改键位）
- **验收**：宿主改键位 → 游戏内 1s 内生效；通道断开时一切回退现状。

---

## 阶段 5 — 差异化主战场（最后做）

### 5.0 前置 spike：编辑器外置权限链路（原 #6 的闸门）
- **任务**：验证外部进程方案三要素——a) 独立 NSWindow 高层级叠加不抢游戏焦点；b) Accessibility API 获取游戏窗口 bounds（需用户授权，验证授权流程与拒授权降级）；c) 窗口坐标 ↔ 游戏内坐标换算精度。spike 不通过则 #6 不立项。

### 5.1 适配规则数据化（原 #7）
- **任务**：hook 生效条件（bundleId/引擎检测/SDK 指纹）外置为**签名数据包**（先内置打包，后远程更新）；含版本号与离线兜底。
- **风险**：远程更新通道即攻击面，必须验签 + 降级策略。

---

## 明确暂缓 / 不做

- **IOKit HID 直读手柄（原 #8）**：`_dispatch_main_queue_callback_4CF`（`PlayInput.swift:14-21`）的存在是为了让 GCController 事件在 CADisplayLink 帧内被派发。直读 HID 需重实现 GameController 全套语义（按钮映射/摇杆曲线/多手柄枚举），成本远超删一个私有符号的收益。**保留现状 + 注释说明 + 观察项**。

## 目标架构演进（修订版）

原方案的多 dylib 拆分会改变与宿主的安装契约（注入 1 个 framework → N 个）。修订为两步走：

1. **近期（阶段 0-3）**：维持单 framework + AKInterface.bundle 物理结构不变，内部按 module 隔离（PCLog / HookRegistry / Contracts / Geometry / Tests）。
2. **远期（阶段 4-5 真有差异化发布节奏时）**：再评估拆 `runtime-core`（仅平台伪造，极稳）/ `runtime-scene` / `runtime-input` / `runtime-services`。

```
宿主 PlayCover (fork) ── plist(现状) + UDS(阶段4) + 契约包(阶段3) ──▶ PlayTools.framework
                                                                      ├─ PCLog / HookDiagnostics (P0)
                                                                      ├─ HookRegistry + Installer (P1)
                                                                      ├─ ScreenGeometry 纯逻辑 (P2)
                                                                      ├─ AKInterface.bundle (保留原设计)
                                                                      └─ PlayToolsTests (P2)
独立进程：键位编辑器 (P5.0 spike 通过后)
```
