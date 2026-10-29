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
- **状态**：✅ 完成（target 部分）— 无 host 的逻辑测试 bundle（`com.apple.product-type.bundle.unit-test`，不设 TEST_HOST）。**关键设计**：被测纯逻辑源文件直接双编译进测试 target，**不链接 PlayTools.framework**——framework 的 `+load`/constructor 会执行 DYLD_INTERPOSE 与 SecItem 挂钩，绝不能进测试 runner 进程。命令：`xcodebuild test -project PlayTools.xcodeproj -scheme PlayTools -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`（共享 scheme 已挂 TestAction）。✅ CI test job 已补（`.github/workflows/Tests.yml`，macos-latest + 动态选取 runner 上首个 iPhone 模拟器，避免镜像间模拟器名漂移；SwiftLint job 保持不动）。

### 2.2 几何变换纯函数化 + 用例
- **任务**：`PlayScreen.swift` 的 `toAspectRatio*` 家族改为 `ScreenGeometry` 结构（宽高/旋转/scaler 参数注入，消除全局 `let` 依赖）；覆盖 16:9/4:3/自定义/inverse/旋转矩阵用例。
- **验收**：变换逻辑全量单测覆盖。
- **状态**：✅ 完成 — 新增 `PlayTools/Utils/ScreenGeometry.swift`（仅 CoreGraphics，width/height/scaler 全注入；aspectRatio/size/sizeReversed/rect(multiplier:)/rectReversed），双编译进 PlayToolsTests。`PlayScreen.swift` 的 4 个全局 `let`（mainScreenWidth/mainScreenHeight/customScaler/isInvertFixEnabled）与 CGSize/CGRect 扩展全部改为委托懒加载全局 `screenGeometry`（首访问时机与原 lazy 语义一致，含 inverse 预交换）；对外 API 签名不变，调用点零改动。11 个用例：16:9 横/竖、4:3、自定义 64:27、正方形、size 对、scaler 乘算、reversed 保原点、inverse 工厂交换语义。旋转矩阵实际参与的是键位路径（displayRotation 在 Keymapping/Editor 侧），在 2.3 补。

### 2.3 键位坐标换算用例
- **任务**：keymap 相对坐标（0-1）↔ 屏幕绝对坐标换算抽纯函数 + 用例（含 inverse、分辨率变化）。
- **状态**：✅ 完成 — 新增 `PlayTools/Utils/KeymapCoordinates.swift`（CoreGraphics only，实时屏幕宽高注入；absolute/relative 的 x/y/size 六个换算 + percent=长边/100 语义），双编译进 PlayToolsTests。`PlayScreen.swift` 的 `CGFloat` relative/absolute 扩展改为委托每次访问重建的 `keymapCoordinates`（与原直接读 `screen` 的实时性一致，窗口缩放即时生效）。9 个用例：轴映射、percent 单位、往返一致性、三种分辨率下同一相对坐标、inverse 竖屏轴交换、0/1 边界。

### 2.4 PlayChain 序列化用例
- **任务**：`PlayKeychain` add/copyMatching/update/delete 的 plist 语义 + `PlayKeychainDB` SQLite 持久化用例（临时目录）。
- **状态**：✅ 完成 — 11 个用例（add/query 往返、copyMatching 数据/存在性检查/未找到/r_Attributes 剥离 v_Data/matchLimitAll 数组、update 替换与未找到、delete 删除与未找到、跨 DB 实例持久化）。DI 设计：`PlayKeychainDB(directoryURL:)` 注入临时目录 + `PlayKeychain.playChainDB` 可替换（生产恒为 .shared）；依赖闭包 6 文件双编译进测试 target（PlayedApple/PlayedAppleDB/PlayedAppleDBConstants/PlaySettings/PCLog/DiscordActivity，均无 +load 副作用）。
- **附带修复 2 个真实生产 bug**（用例暴露）：① `connectToDB` 短路逻辑——`alreadyCreated` 在 `sqlite3_open`（会创建空文件）之前检查，全新 DB 上 `!alreadyCreated` 为真导致 `structDB` 从不执行、首连必失败 errSecIO（生产中被 db 文件跨启动持久化掩盖，仅首个 keychain 操作失败；测试每用例全新临时目录故必现）；修复为每次连接都跑幂等 structDB。② `delete` 的 `sqlite3_step == SQLITE_OK` 判断——DELETE 成功返回 SQLITE_DONE，导致 SecItemDelete 模拟层**删除成功却返回 errSecIO**；修为 SQLITE_DONE。另：PlayedAppleDBConstants.swift 补上显式 `import Security`（原先靠 PlayTools 桥接头才编译通过，双编译进无桥接头的测试 target 时暴露）。全套 32 用例绿（21 旧 + 11 新）。

### 2.5 TouchSink seam
- **任务**：`ActionDispatcher` → `Toucher` 之间抽协议，逻辑层可注入 fake sink 单测分发正确性。
- **状态**：✅ 完成 — 新增 `TouchSink` 协议 + 纯逻辑 `TouchSession`（began 分配/重复抑制、moved/ended 孤儿抑制、负 tid 释放会话），双编译进测试 target；`Toucher.touchcam` 的门控逻辑改为复用 `TouchSession`（行为等价）；PlayAction 全部 25 处 `Toucher.touchcam` 调用改走可注入全局 `touchSink`（默认 `ToucherSink.shared` 转发回 Toucher，生产行为不变）。8 个用例：4 门控 + 2 tid 生命周期 + 2 fake sink 经协议类型分发（begin/move/end 序列、重复 began 与孤儿事件抑制）。
- **遗留**：Action 状态机（JoystickAction 键位→触点换算、CameraAction 限速等）无法双编译——`DraggableButtonAction` 直呼 `AKInterface.shared!`（macOS bundle 协议，测试 target 无此类型），且 ActionDispatcher 依赖 Atomics SPM 包。测 Action 层需先把 AKInterface 调用抽 seam + 测试 target 挂 package，留待后续。

---

## 阶段 3 — 设置契约统一（原 #4）

### 3.1 仓库内去重（先做）
- **任务**：删除 `AKPlugin.swift` 的 `AKAppSettingsData`；`AppSettingsData` 移入单文件 `PlayToolsContracts.swift`，同时加入 PlayTools 与 AKInterface 两个 target 的 Sources（单一源文件双编译，无包依赖）。
- **验收**：仓库内 schema 只剩一份；AKInterface 行为不变（hideTitleBar/floatingWindow/aspectRatio 读取路径改走共享类型）。
- **状态**：✅ 完成 — 仓库根新增 `PlayToolsContracts.swift`（`AppSettingsData` 单一来源，三 target 编译：PlayTools / AKInterface / PlayToolsTests）；`DiscordActivity.swift` 追加编译进 AKInterface（schema 依赖，纯 Foundation）；`AKPlugin.swift` 删除 `AKAppSettingsData` 改解码共享类型，三处读取路径（hideTitleBar/floatingWindow/aspectRatio）零改动；`PlaySettings.swift` 移除重复 struct。**顺带落地 3.2 要求的 decode 兼容规则**：`AppSettingsData` 自定义 `init(from:)` 全字段 `decodeIfPresent ?? 默认值`——旧宿主写入的缺字段 plist 不再把整个设置重置为默认（此前任何缺失键都会让 decode 抛错兜底全默认，新增字段即砖）；`discordActivity` 子解码失败降级默认实例。4 个用例（部分 plist 保留已写值、空 plist 全默认、损坏 discordActivity 降级、编解码往返）。AKInterface 双架构独立构建验证通过（`xcodebuild -target AKInterface`）。全套 44 用例绿。

### 3.2 抽 SwiftPM 契约包
- **任务**：`PlayToolsContract` package（纯 Foundation Codable），本仓库与 fork 的 PlayCover 共同依赖；`version` 字段配套 decode 兼容规则。
- **验收**：三份拷贝归一；宿主 fork 切换后装老游戏不崩、新字段缺省合理。
- **状态**：🟡 暂缓 — decode 兼容规则已在 3.1 落地（全字段 decodeIfPresent + 默认值）。SwiftPM 包抽取与"三份归一"需要宿主 PlayCover fork 仓库协同（第三份拷贝在宿主侧），本仓库内无对象；待宿主 fork 统一时执行。当前单文件三 target 编译已消除仓库内重复。

---

## 阶段 4 — UDS 活通道（原 #5，产品力开始）

- **任务**：
  1. ✅ 协议：Unix domain socket + JSON lines，版本握手；指令集 `keymap.update` / `settings.refresh` / `diag.dump` / `log.level`（`PlayTools/Utils/PCChannel.swift`，纯 Foundation，双编译进 PlayToolsTests；`isOK` 字段经 CodingKeys 映射保持线上 JSON 键 `ok`；未知命令/未知字段忽略保证前向兼容。8 个用例：编解码往返、行分帧含半包、前向兼容。）
  2. ✅ 运行时侧客户端（`PCChannelSession` 字节流重组 + `PCChannelTransport`/`PCChannelSocketTransport` POSIX AF_UNIX 阻塞传输 + `PCChannelClient` 工作线程（握手、退避重连 0.5→8s 后放弃、命令分发表）。`PlayCover.launch` 非 safeMode 时启动。失败全程静默：无宿主时行为与现状完全一致。测试：分帧重组 5 例（含多字节字符跨 chunk、坏行丢弃）+ POSIX 传输 3 例（含 sun_path 超长拒绝、真 socket 往返与 EOF），全套 60 绿。）
  3. 宿主侧服务端（fork 的 PlayCover）
  4. ✅ 第一个落地功能：键位热更新（运行时侧）：`PlayCover.launch` 注册 `keymap.update` → 主队列 `ActionDispatcher.build()`（与游戏内切换键位菜单完全同路径；`keymap.currentKeymap` 每次访问都从磁盘重读 plist，重建即生效）；`diag.dump` → `HookDiagnostics.exportSnapshot()` 重导 hook 快照。`settings.refresh` 暂不注册——`PlaySettings` 全部为一次性 `lazy` 缓存，可刷新集合待 4.3 宿主侧落地时一并定义。客户端管线集成测试 3 例（脚本化传输：握手、单/多消息按序分发、未知命令不触达 handler），全套 63 绿。
- **验收**：宿主改键位 → 游戏内 1s 内生效；通道断开时一切回退现状。
- **状态**：🟡 4.1 协议编解码、4.2 运行时 UDS 客户端、4.4 键位热更新（运行时侧）已落地（测试 63 绿）；剩余 4.3 宿主侧服务端（PlayCover 仓库，socket 路径约定 `/tmp/PlayCover/PC-<bundleID>.sock`）与端到端验收（宿主改键位 → 游戏内 1s 生效）。

---

## 阶段 5 — 差异化主战场（最后做）

### 5.0 前置 spike：编辑器外置权限链路（原 #6 的闸门）
- **任务**：验证外部进程方案三要素——a) 独立 NSWindow 高层级叠加不抢游戏焦点；b) Accessibility API 获取游戏窗口 bounds（需用户授权，验证授权流程与拒授权降级）；c) 窗口坐标 ↔ 游戏内坐标换算精度。spike 不通过则 #6 不立项。
- **状态**：🟡 验证工具已就绪（`Spike/EditorExternalizationSpike/main.swift`，独立 swiftc 编译，不进 Xcode 工程；swiftlint --strict 通过）：
  - a) `.borderless + .nonactivatingPanel` 浮层，`orderFrontRegardless` + `ignoresMouseEvents`，每秒跟随目标窗口；
  - b) `AXIsProcessTrustedWithOptions` 授权门，未授权时打印降级路径并以 EX_TEMPFAIL 退出（不崩溃）；`kAXWindowsAttribute/kAXPositionAttribute/kAXSizeAttribute` 取 bounds；
  - c) AX 左上原点 ↔ 游戏左下原点换算含多屏 offset，每秒输出换算结果供比对。
  - **手动验收步骤**（需真机 + 真游戏）：`swiftc -O -o spike main.swift -framework AppKit -framework ApplicationServices` → 启动游戏取 pid → `./spike <pid> 15` → 核对：① 游戏全程保持键盘焦点（点击浮层区域也不切换）；② 移动/缩放游戏窗口时红色浮层 1s 内贴合；③ 输出的 game-space origin 与游戏内已知点位吻合。三项全过则 #6 立项。

### 5.1 适配规则数据化（原 #7）
- **任务**：hook 生效条件（bundleId/引擎检测/SDK 指纹）外置为**签名数据包**（先内置打包，后远程更新）；含版本号与离线兜底。
- **风险**：远程更新通道即攻击面，必须验签 + 降级策略。
- **状态**：🟡 数据层+镜像已落地：
  - `HookRulePack.swift`（纯模型：规则 = selector/replacement/candidates/policy + `when` 命名事实条件，AND 语义，未知事实**fail-closed**——错装 hook 比漏装更危险；版本校验、重复 id/空字段校验）+ `HookRulePackLoader.swift`（Ed25519 签名信封：payload 原始字节签名，免 canonical JSON；任何失败返回 nil 走兜底）。
  - `HookFactsInput`（启动期环境快照，纯结构）+ `HookRuleFacts.dict`（事实命名协议）；`allSpecs` 重构为纯函数（`HookSpecMatrix.allSpecs(facts:)`，F 组条件改为捕获 bool，PlayInfo/PlaySettings 读取移到 run()）；`HookSpecModel.swift` 拆出纯模型使 spec 矩阵可双编译。
  - `HookRulePackDefaults.bundledJSON`：37 条规则逐条镜像代码矩阵；`HookRuleAdapter` 把激活规则映射回 HookSpec（条件已在事实快照求值）。
  - **等价测试**（防漂移）：32 个显示矩阵组合 ×2 个条件修复组合，断言 pack 路径与代码路径产出**完全相同**的安装集（id/selector/replacement/candidates/policy 全序比较）。全套 81 绿。
  - 待做：安装路径切换（外部签名包 → 内置包 → 代码矩阵三级兜底）+ 外部包路径约定 + 私钥/公钥管理（✅ 签名工具已就绪：`Spike/RulePackSigner/main.swift`，swiftc 独立编译的 `genkeys`/`sign`/`verify` CLI，信封与 `HookRulePackLoader` 逐字节同构——签名覆盖 pack 原始字节不重编码；篡改 payload 验证拒绝、缺钥 EX_CONFIG、坏命令 EX_USAGE 均实测）。
  - ✅ **安装路径已切换**：`HookRuleResolver`（纯函数三级解析）+ `HookRuleRegistry.run()` 改为「外部签名包（`~/Library/Containers/io.playcover.PlayCover/Rule Packs/<bundleID>.json`，Ed25519 验签，失败即弃）→ 内置包 → 代码矩阵兜底」，每级来源写入日志。`HookRulePackPinning.pinnedPublicKey` 暂为 nil——发布前生成密钥对并钉入公钥前，外部包通道整体禁用（fail-safe）。解析器 4 用例（外部优先/内置次之/双缺走代码/内置与代码安装集一致），全套 85 绿。**5.1 运行时侧完成**；剩余：发布密钥对生成并钉入公钥（工具已备，`Spike/RulePackSigner`）+ 宿主侧下发链路 + 远程通道。

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
